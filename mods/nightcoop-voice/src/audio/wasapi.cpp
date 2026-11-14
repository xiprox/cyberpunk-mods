#include "audio/wasapi.hpp"

#include <windows.h>

#include <initguid.h>

#include <mmdeviceapi.h>

#include <audioclient.h>
#include <propidl.h>
#include <propkeydef.h>

#include <functiondiscoverykeys_devpkey.h>
#include <ksmedia.h>

#include <thread>

namespace nv
{
namespace
{
constexpr REFERENCE_TIME kHundredNsPerMs = 10000;
constexpr int kCaptureBufferMs = 100;
constexpr int kRenderBufferMs = 60;
constexpr int kRenderTargetMs = 30;

std::string ToUtf8(const wchar_t* aText)
{
    if (!aText)
    {
        return {};
    }
    const int size = WideCharToMultiByte(CP_UTF8, 0, aText, -1, nullptr, 0, nullptr, nullptr);
    if (size <= 1)
    {
        return {};
    }
    std::string out(static_cast<size_t>(size - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, aText, -1, out.data(), size, nullptr, nullptr);
    return out;
}

std::wstring ToWide(const std::string& aText)
{
    const int size = MultiByteToWideChar(CP_UTF8, 0, aText.c_str(), -1, nullptr, 0);
    if (size <= 1)
    {
        return {};
    }
    std::wstring out(static_cast<size_t>(size - 1), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, aText.c_str(), -1, out.data(), size);
    return out;
}

template<typename T>
void Release(T*& aPointer)
{
    if (aPointer)
    {
        aPointer->Release();
        aPointer = nullptr;
    }
}

IMMDevice* FindDevice(const std::string& aId, EDataFlow aFlow)
{
    IMMDeviceEnumerator* enumerator = nullptr;
    HRESULT result = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
    if (FAILED(result))
    {
        return nullptr;
    }
    IMMDevice* device = nullptr;
    if (!aId.empty())
    {
        // A device unplugged since it was chosen falls through to the default.
        if (FAILED(enumerator->GetDevice(ToWide(aId).c_str(), &device)))
        {
            Logf(LogWarn, "audio: the chosen device is gone, using the default");
            device = nullptr;
        }
    }
    if (!device)
    {
        enumerator->GetDefaultAudioEndpoint(aFlow, eConsole, &device);
    }
    enumerator->Release();
    return device;
}

StreamFormat ParseFormat(const WAVEFORMATEX& aFormat)
{
    StreamFormat format;
    format.channels = aFormat.nChannels;
    format.rate = static_cast<int>(aFormat.nSamplesPerSec);
    format.bytesPerSample = aFormat.wBitsPerSample / 8;
    format.isFloat = aFormat.wFormatTag == WAVE_FORMAT_IEEE_FLOAT;
    if (aFormat.wFormatTag == WAVE_FORMAT_EXTENSIBLE)
    {
        const auto& extensible = reinterpret_cast<const WAVEFORMATEXTENSIBLE&>(aFormat);
        format.isFloat = IsEqualGUID(extensible.SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) != 0;
    }
    return format;
}

float ReadSample(const uint8_t* aData, const StreamFormat& aFormat)
{
    if (aFormat.isFloat && aFormat.bytesPerSample == 4)
    {
        float value;
        memcpy(&value, aData, 4);
        return value;
    }
    switch (aFormat.bytesPerSample)
    {
    case 2:
    {
        int16_t value;
        memcpy(&value, aData, 2);
        return static_cast<float>(value) / 32768.f;
    }
    case 3:
    {
        const int32_t value = (static_cast<int32_t>(aData[2]) << 24) | (static_cast<int32_t>(aData[1]) << 16) |
                              (static_cast<int32_t>(aData[0]) << 8);
        return static_cast<float>(value) / 2147483648.f;
    }
    case 4:
    {
        int32_t value;
        memcpy(&value, aData, 4);
        return static_cast<float>(value) / 2147483648.f;
    }
    default:
        return 0.f;
    }
}

void WriteSample(uint8_t* aData, const StreamFormat& aFormat, float aValue)
{
    const float clamped = std::clamp(aValue, -1.f, 1.f);
    if (aFormat.isFloat && aFormat.bytesPerSample == 4)
    {
        memcpy(aData, &clamped, 4);
        return;
    }
    switch (aFormat.bytesPerSample)
    {
    case 2:
    {
        const int16_t value = static_cast<int16_t>(clamped * 32767.f);
        memcpy(aData, &value, 2);
        break;
    }
    case 3:
    {
        const int32_t value = static_cast<int32_t>(clamped * 8388607.f);
        aData[0] = static_cast<uint8_t>(value);
        aData[1] = static_cast<uint8_t>(value >> 8);
        aData[2] = static_cast<uint8_t>(value >> 16);
        break;
    }
    case 4:
    {
        const int32_t value = static_cast<int32_t>(clamped * 2147483647.f);
        memcpy(aData, &value, 4);
        break;
    }
    default:
        break;
    }
}

// Asks for exactly what we work in and lets Windows convert; a driver that refuses gets its own format and we convert.
HRESULT InitClient(IAudioClient* aClient, int aChannels, DWORD aFlags, int aBufferMs, StreamFormat& aOut)
{
    WAVEFORMATEXTENSIBLE wanted{};
    wanted.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
    wanted.Format.nChannels = static_cast<WORD>(aChannels);
    wanted.Format.nSamplesPerSec = kRate;
    wanted.Format.wBitsPerSample = 32;
    wanted.Format.nBlockAlign = static_cast<WORD>(aChannels * 4);
    wanted.Format.nAvgBytesPerSec = kRate * wanted.Format.nBlockAlign;
    wanted.Format.cbSize = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
    wanted.Samples.wValidBitsPerSample = 32;
    wanted.dwChannelMask = aChannels == 1 ? SPEAKER_FRONT_CENTER : SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT;
    wanted.SubFormat = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;

    const REFERENCE_TIME buffer = aBufferMs * kHundredNsPerMs;
    const DWORD convert = AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY;
    HRESULT result = aClient->Initialize(AUDCLNT_SHAREMODE_SHARED, aFlags | convert, buffer, 0, &wanted.Format, nullptr);
    if (SUCCEEDED(result))
    {
        aOut = ParseFormat(wanted.Format);
        return result;
    }

    WAVEFORMATEX* mix = nullptr;
    result = aClient->GetMixFormat(&mix);
    if (FAILED(result))
    {
        return result;
    }
    result = aClient->Initialize(AUDCLNT_SHAREMODE_SHARED, aFlags, buffer, 0, mix, nullptr);
    if (SUCCEEDED(result))
    {
        aOut = ParseFormat(*mix);
    }
    CoTaskMemFree(mix);
    return result;
}
} // namespace

ComThread::ComThread()
{
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
}

ComThread::~ComThread()
{
    CoUninitialize();
}

std::vector<DeviceInfo> ListDevices(bool aCapture)
{
    std::vector<DeviceInfo> devices;
    // The game thread has its own COM setup, which this mustn't disturb.
    std::thread worker([&] {
        ComThread com;
        IMMDeviceEnumerator* enumerator = nullptr;
        if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator))))
        {
            return;
        }
        IMMDeviceCollection* collection = nullptr;
        if (SUCCEEDED(enumerator->EnumAudioEndpoints(aCapture ? eCapture : eRender, DEVICE_STATE_ACTIVE, &collection)))
        {
            UINT count = 0;
            collection->GetCount(&count);
            for (UINT i = 0; i < count; ++i)
            {
                IMMDevice* device = nullptr;
                if (FAILED(collection->Item(i, &device)))
                {
                    continue;
                }
                DeviceInfo info;
                LPWSTR id = nullptr;
                if (SUCCEEDED(device->GetId(&id)))
                {
                    info.id = ToUtf8(id);
                    CoTaskMemFree(id);
                }
                IPropertyStore* store = nullptr;
                if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, &store)))
                {
                    PROPVARIANT name;
                    PropVariantInit(&name);
                    if (SUCCEEDED(store->GetValue(PKEY_Device_FriendlyName, &name)) && name.vt == VT_LPWSTR)
                    {
                        info.name = ToUtf8(name.pwszVal);
                    }
                    PropVariantClear(&name);
                    store->Release();
                }
                if (info.name.empty())
                {
                    info.name = info.id;
                }
                devices.push_back(std::move(info));
                device->Release();
            }
            collection->Release();
        }
        enumerator->Release();
    });
    worker.join();
    return devices;
}

CaptureStream::~CaptureStream()
{
    Close();
}

bool CaptureStream::Open(const std::string& aId, bool aLoopback)
{
    Close();
    IMMDevice* device = FindDevice(aId, aLoopback ? eRender : eCapture);
    if (!device)
    {
        Logf(LogWarn, "audio: no %s device", aLoopback ? "output" : "microphone");
        return false;
    }
    HRESULT result = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(&m_client));
    device->Release();
    if (FAILED(result))
    {
        m_client = nullptr;
        return false;
    }

    // Loopback streams don't signal an event on every Windows version, so they're polled instead.
    const DWORD flags = aLoopback ? AUDCLNT_STREAMFLAGS_LOOPBACK : AUDCLNT_STREAMFLAGS_EVENTCALLBACK;
    result = InitClient(m_client, aLoopback ? 2 : 1, flags, kCaptureBufferMs, m_format);
    if (SUCCEEDED(result) && !aLoopback)
    {
        m_event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        result = m_client->SetEventHandle(m_event);
    }
    if (SUCCEEDED(result))
    {
        result = m_client->GetService(IID_PPV_ARGS(&m_capture));
    }
    if (SUCCEEDED(result))
    {
        result = m_client->Start();
    }
    if (FAILED(result))
    {
        Logf(LogWarn, "audio: could not open the %s (0x%08lx)", aLoopback ? "output loopback" : "microphone",
             static_cast<unsigned long>(result));
        Close();
        return false;
    }
    m_resampler.SetRatio(m_format.rate, kRate);
    Logf(LogInfo, "audio: %s open: %d Hz, %d channel(s), %d bytes%s", aLoopback ? "output loopback" : "microphone",
         m_format.rate, m_format.channels, m_format.bytesPerSample, m_format.isFloat ? " float" : "");
    return true;
}

void CaptureStream::Close()
{
    if (m_client)
    {
        m_client->Stop();
    }
    Release(m_capture);
    Release(m_client);
    if (m_event)
    {
        CloseHandle(m_event);
        m_event = nullptr;
    }
}

bool CaptureStream::Read(std::vector<float>& aOut, int aWaitMs)
{
    if (!m_capture)
    {
        return false;
    }
    UINT32 packet = 0;
    HRESULT result = m_capture->GetNextPacketSize(&packet);
    if (SUCCEEDED(result) && packet == 0 && aWaitMs > 0)
    {
        if (m_event)
        {
            WaitForSingleObject(m_event, static_cast<DWORD>(aWaitMs));
        }
        else
        {
            Sleep(static_cast<DWORD>(aWaitMs));
        }
        result = m_capture->GetNextPacketSize(&packet);
    }

    const int frameBytes = m_format.channels * m_format.bytesPerSample;
    while (SUCCEEDED(result) && packet > 0)
    {
        BYTE* data = nullptr;
        UINT32 frames = 0;
        DWORD flags = 0;
        result = m_capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
        if (FAILED(result))
        {
            break;
        }
        const bool silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0;
        for (UINT32 frame = 0; frame < frames; ++frame)
        {
            float mono = 0.f;
            if (!silent)
            {
                const uint8_t* start = data + static_cast<size_t>(frame) * frameBytes;
                for (int channel = 0; channel < m_format.channels; ++channel)
                {
                    mono += ReadSample(start + static_cast<size_t>(channel) * m_format.bytesPerSample, m_format);
                }
                mono /= static_cast<float>(m_format.channels);
            }
            if (m_format.rate == kRate)
            {
                aOut.push_back(mono);
            }
            else
            {
                m_resampler.Process(&mono, 1, [&](float aSample) { aOut.push_back(aSample); });
            }
        }
        result = m_capture->ReleaseBuffer(frames);
        if (SUCCEEDED(result))
        {
            result = m_capture->GetNextPacketSize(&packet);
        }
    }
    return SUCCEEDED(result);
}

RenderStream::~RenderStream()
{
    Close();
}

bool RenderStream::Open(const std::string& aId)
{
    Close();
    IMMDevice* device = FindDevice(aId, eRender);
    if (!device)
    {
        Logf(LogWarn, "audio: no output device");
        return false;
    }
    HRESULT result = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(&m_client));
    device->Release();
    if (FAILED(result))
    {
        m_client = nullptr;
        return false;
    }

    result = InitClient(m_client, 2, AUDCLNT_STREAMFLAGS_EVENTCALLBACK, kRenderBufferMs, m_format);
    if (SUCCEEDED(result))
    {
        m_event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        result = m_client->SetEventHandle(m_event);
    }
    if (SUCCEEDED(result))
    {
        result = m_client->GetBufferSize(&m_bufferFrames);
    }
    if (SUCCEEDED(result))
    {
        result = m_client->GetService(IID_PPV_ARGS(&m_render));
    }
    if (SUCCEEDED(result))
    {
        result = m_client->Start();
    }
    if (FAILED(result))
    {
        Logf(LogWarn, "audio: could not open the output (0x%08lx)", static_cast<unsigned long>(result));
        Close();
        return false;
    }
    m_targetFrames = static_cast<unsigned int>(m_format.rate * kRenderTargetMs / 1000);
    m_targetFrames = std::min(m_targetFrames, m_bufferFrames);
    m_resamplerLeft.SetRatio(kRate, m_format.rate);
    m_resamplerRight.SetRatio(kRate, m_format.rate);
    Logf(LogInfo, "audio: output open: %d Hz, %d channel(s), %d bytes%s", m_format.rate, m_format.channels,
         m_format.bytesPerSample, m_format.isFloat ? " float" : "");
    return true;
}

void RenderStream::Close()
{
    if (m_client)
    {
        m_client->Stop();
    }
    Release(m_render);
    Release(m_client);
    if (m_event)
    {
        CloseHandle(m_event);
        m_event = nullptr;
    }
    m_pendingStereo.clear();
}

int RenderStream::Wanted()
{
    if (!m_client)
    {
        return -1;
    }
    UINT32 padding = 0;
    if (FAILED(m_client->GetCurrentPadding(&padding)))
    {
        return -1;
    }
    if (padding >= m_targetFrames)
    {
        return 0;
    }
    const UINT32 missing = m_targetFrames - padding;
    return static_cast<int>(static_cast<double>(missing) * kRate / m_format.rate);
}

bool RenderStream::Write(const float* aStereo, int aFrames)
{
    if (!m_render)
    {
        return false;
    }

    if (m_format.rate == kRate)
    {
        m_pendingStereo.insert(m_pendingStereo.end(), aStereo, aStereo + static_cast<ptrdiff_t>(aFrames) * 2);
    }
    else
    {
        m_left.clear();
        m_right.clear();
        for (int i = 0; i < aFrames; ++i)
        {
            m_resamplerLeft.Process(&aStereo[i * 2], 1, [&](float aSample) { m_left.push_back(aSample); });
            m_resamplerRight.Process(&aStereo[i * 2 + 1], 1, [&](float aSample) { m_right.push_back(aSample); });
        }
        const size_t both = std::min(m_left.size(), m_right.size());
        for (size_t i = 0; i < both; ++i)
        {
            m_pendingStereo.push_back(m_left[i]);
            m_pendingStereo.push_back(m_right[i]);
        }
    }

    UINT32 padding = 0;
    if (FAILED(m_client->GetCurrentPadding(&padding)))
    {
        return false;
    }
    const UINT32 room = m_bufferFrames - padding;
    const UINT32 frames = std::min(room, static_cast<UINT32>(m_pendingStereo.size() / 2));
    if (frames == 0)
    {
        return true;
    }

    BYTE* data = nullptr;
    if (FAILED(m_render->GetBuffer(frames, &data)))
    {
        return false;
    }
    const int sampleBytes = m_format.bytesPerSample;
    for (UINT32 frame = 0; frame < frames; ++frame)
    {
        const float left = m_pendingStereo[static_cast<size_t>(frame) * 2];
        const float right = m_pendingStereo[static_cast<size_t>(frame) * 2 + 1];
        uint8_t* start = data + static_cast<size_t>(frame) * m_format.channels * sampleBytes;
        for (int channel = 0; channel < m_format.channels; ++channel)
        {
            float value = 0.f;
            if (m_format.channels == 1)
            {
                value = (left + right) * 0.5f;
            }
            else if (channel < 2)
            {
                value = channel == 0 ? left : right;
            }
            WriteSample(start + static_cast<size_t>(channel) * sampleBytes, m_format, value);
        }
    }
    if (FAILED(m_render->ReleaseBuffer(frames, 0)))
    {
        return false;
    }
    m_pendingStereo.erase(m_pendingStereo.begin(), m_pendingStereo.begin() + static_cast<ptrdiff_t>(frames) * 2);
    return true;
}

void RenderStream::Wait(int aMs)
{
    if (m_event)
    {
        WaitForSingleObject(m_event, static_cast<DWORD>(aMs));
    }
    else
    {
        Sleep(static_cast<DWORD>(aMs));
    }
}
} // namespace nv
