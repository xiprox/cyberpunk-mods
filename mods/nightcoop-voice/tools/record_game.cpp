// Records what the default output device plays to a WAV, for trying effects on the game's sound outside the game.
// Page Up starts and stops it: two rising beeps mean it's recording, two falling ones that it stopped, two low ones that it
// couldn't start. No beep is in the recording. While this runs, Page Up belongs to it and the game doesn't get the key.
//
//   record_game [folder]           records into folder (default: recordings), one file per start
//   record_game --test <seconds>   records once straight away, with no key and no beeps
#include <windows.h>

#include <initguid.h>

#include <mmdeviceapi.h>

#include <audioclient.h>
#include <ksmedia.h>
#include <mmsystem.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <string>
#include <vector>

namespace
{
constexpr int kHotkeyId = 1;
constexpr double kPi = 3.14159265358979323846;
constexpr DWORD kAfterBeepMs = 200; // the beep's tail can still be on its way out when PlaySound returns

std::atomic<bool> g_quit{false};

BOOL WINAPI OnConsoleClose(DWORD aEvent)
{
    g_quit.store(true);
    if (aEvent == CTRL_CLOSE_EVENT)
    {
        Sleep(2000); // the process ends when this returns, so give the main loop time to finish the file
    }
    return TRUE;
}

// Float WAV, with its sizes written again every second so a recording cut off by a crash still opens.
class WavWriter
{
public:
    bool Open(const std::filesystem::path& aPath, int aChannels, int aRate)
    {
        m_file = _wfopen(aPath.c_str(), L"wb");
        if (!m_file)
        {
            return false;
        }
        m_channels = aChannels;
        m_bytes = 0;
        const uint16_t format = 3; // IEEE float
        const uint16_t channels = static_cast<uint16_t>(aChannels);
        const uint32_t rate = static_cast<uint32_t>(aRate);
        const uint16_t bits = 32;
        const uint16_t align = static_cast<uint16_t>(channels * 4);
        const uint32_t byteRate = rate * align;
        const uint32_t zero = 0;
        const uint32_t fmtSize = 16;
        std::fwrite("RIFF", 1, 4, m_file);
        std::fwrite(&zero, 4, 1, m_file);
        std::fwrite("WAVEfmt ", 1, 8, m_file);
        std::fwrite(&fmtSize, 4, 1, m_file);
        std::fwrite(&format, 2, 1, m_file);
        std::fwrite(&channels, 2, 1, m_file);
        std::fwrite(&rate, 4, 1, m_file);
        std::fwrite(&byteRate, 4, 1, m_file);
        std::fwrite(&align, 2, 1, m_file);
        std::fwrite(&bits, 2, 1, m_file);
        std::fwrite("data", 1, 4, m_file);
        std::fwrite(&zero, 4, 1, m_file);
        return true;
    }

    void Write(const std::vector<float>& aSamples)
    {
        if (m_file && !aSamples.empty())
        {
            std::fwrite(aSamples.data(), sizeof(float), aSamples.size(), m_file);
            m_bytes += static_cast<uint32_t>(aSamples.size() * sizeof(float));
        }
    }

    void WriteSizes()
    {
        if (!m_file)
        {
            return;
        }
        const long end = std::ftell(m_file);
        const uint32_t riff = 36 + m_bytes;
        std::fseek(m_file, 4, SEEK_SET);
        std::fwrite(&riff, 4, 1, m_file);
        std::fseek(m_file, 40, SEEK_SET);
        std::fwrite(&m_bytes, 4, 1, m_file);
        std::fseek(m_file, end, SEEK_SET);
        std::fflush(m_file);
    }

    void Close()
    {
        WriteSizes();
        if (m_file)
        {
            std::fclose(m_file);
        }
        m_file = nullptr;
    }

    double Seconds(int aRate) const
    {
        return static_cast<double>(m_bytes) / (sizeof(float) * m_channels * aRate);
    }

private:
    FILE* m_file = nullptr;
    int m_channels = 2;
    uint32_t m_bytes = 0;
};

// What the default output plays, as interleaved stereo float. More channels are folded down to two.
class Loopback
{
public:
    ~Loopback()
    {
        Close();
    }

    bool Open()
    {
        IMMDeviceEnumerator* enumerator = nullptr;
        IMMDevice* device = nullptr;
        bool ok = SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                             reinterpret_cast<void**>(&enumerator))) &&
                  SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device)) &&
                  SUCCEEDED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(&m_client))) &&
                  SUCCEEDED(m_client->GetMixFormat(&m_mix));
        if (ok)
        {
            m_channels = m_mix->nChannels;
            m_rate = static_cast<int>(m_mix->nSamplesPerSec);
            m_float = m_mix->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
                      (m_mix->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
                       IsEqualGUID(reinterpret_cast<WAVEFORMATEXTENSIBLE*>(m_mix)->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT));
            m_bits = m_mix->wBitsPerSample;
            ok = (m_float && m_bits == 32) || (!m_float && m_bits == 16);
            if (!ok)
            {
                std::printf("The output's format (%d bits, %s) isn't one this reads.\n", m_bits, m_float ? "float" : "integer");
            }
        }
        ok = ok &&
             SUCCEEDED(m_client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 2000000, 0, m_mix, nullptr)) &&
             SUCCEEDED(m_client->GetService(__uuidof(IAudioCaptureClient), reinterpret_cast<void**>(&m_capture))) &&
             SUCCEEDED(m_client->Start());
        if (device)
        {
            device->Release();
        }
        if (enumerator)
        {
            enumerator->Release();
        }
        if (!ok)
        {
            Close();
        }
        return ok;
    }

    void Close()
    {
        if (m_client)
        {
            m_client->Stop();
        }
        if (m_capture)
        {
            m_capture->Release();
        }
        if (m_client)
        {
            m_client->Release();
        }
        if (m_mix)
        {
            CoTaskMemFree(m_mix);
        }
        m_capture = nullptr;
        m_client = nullptr;
        m_mix = nullptr;
    }

    int Rate() const
    {
        return m_rate;
    }

    // Appends whatever has arrived. False means the device is gone.
    bool Read(std::vector<float>& aStereo)
    {
        UINT32 packet = 0;
        while (true)
        {
            if (FAILED(m_capture->GetNextPacketSize(&packet)))
            {
                return false;
            }
            if (packet == 0)
            {
                return true;
            }
            BYTE* data = nullptr;
            UINT32 frames = 0;
            DWORD flags = 0;
            if (FAILED(m_capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr)))
            {
                return false;
            }
            const bool silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0;
            for (UINT32 i = 0; i < frames; ++i)
            {
                float left = 0.f;
                float right = 0.f;
                if (!silent)
                {
                    Fold(data, i, left, right);
                }
                aStereo.push_back(left);
                aStereo.push_back(right);
            }
            m_capture->ReleaseBuffer(frames);
        }
    }

private:
    float Sample(const BYTE* aData, UINT32 aFrame, int aChannel) const
    {
        const size_t index = static_cast<size_t>(aFrame) * m_channels + aChannel;
        if (m_float)
        {
            float value;
            std::memcpy(&value, aData + index * 4, 4);
            return value;
        }
        int16_t value;
        std::memcpy(&value, aData + index * 2, 2);
        return value / 32768.f;
    }

    // Front left and right as they are; centre and the surrounds a little lower on both sides; the bass channel left out.
    void Fold(const BYTE* aData, UINT32 aFrame, float& aLeft, float& aRight) const
    {
        if (m_channels == 1)
        {
            aLeft = aRight = Sample(aData, aFrame, 0);
            return;
        }
        aLeft = Sample(aData, aFrame, 0);
        aRight = Sample(aData, aFrame, 1);
        constexpr float kSide = 0.707f;
        if (m_channels > 2)
        {
            const float centre = Sample(aData, aFrame, 2) * kSide;
            aLeft += centre;
            aRight += centre;
        }
        for (int channel = 4; channel + 1 < m_channels; channel += 2)
        {
            aLeft += Sample(aData, aFrame, channel) * kSide;
            aRight += Sample(aData, aFrame, channel + 1) * kSide;
        }
    }

    IAudioClient* m_client = nullptr;
    IAudioCaptureClient* m_capture = nullptr;
    WAVEFORMATEX* m_mix = nullptr;
    int m_channels = 2;
    int m_rate = 48000;
    int m_bits = 32;
    bool m_float = true;
};

// Two short tones, as a 16-bit WAV in memory for PlaySound.
std::vector<uint8_t> MakeBeeps(double aFirstHz, double aSecondHz)
{
    constexpr int kRate = 48000;
    constexpr double kToneSeconds = 0.09;
    constexpr double kGapSeconds = 0.06;
    constexpr double kFadeSeconds = 0.005;
    constexpr double kLevel = 0.3;
    std::vector<int16_t> samples;
    for (const double hz : {aFirstHz, aSecondHz})
    {
        const int count = static_cast<int>(kToneSeconds * kRate);
        for (int i = 0; i < count; ++i)
        {
            const double t = static_cast<double>(i) / kRate;
            const double fade = std::min({1.0, t / kFadeSeconds, (kToneSeconds - t) / kFadeSeconds});
            samples.push_back(static_cast<int16_t>(std::sin(2.0 * kPi * hz * t) * fade * kLevel * 32767.0));
        }
        samples.insert(samples.end(), static_cast<size_t>(kGapSeconds * kRate), 0);
    }

    const uint32_t dataBytes = static_cast<uint32_t>(samples.size() * 2);
    std::vector<uint8_t> wav(44 + dataBytes);
    const auto put32 = [&](size_t aAt, uint32_t aValue) { std::memcpy(wav.data() + aAt, &aValue, 4); };
    const auto put16 = [&](size_t aAt, uint16_t aValue) { std::memcpy(wav.data() + aAt, &aValue, 2); };
    std::memcpy(wav.data(), "RIFF", 4);
    put32(4, 36 + dataBytes);
    std::memcpy(wav.data() + 8, "WAVEfmt ", 8);
    put32(16, 16);
    put16(20, 1);
    put16(22, 1);
    put32(24, kRate);
    put32(28, kRate * 2);
    put16(32, 2);
    put16(34, 16);
    std::memcpy(wav.data() + 36, "data", 4);
    put32(40, dataBytes);
    std::memcpy(wav.data() + 44, samples.data(), dataBytes);
    return wav;
}

void PlayBeeps(const std::vector<uint8_t>& aWav)
{
    PlaySoundW(reinterpret_cast<LPCWSTR>(aWav.data()), nullptr, SND_MEMORY | SND_SYNC | SND_NODEFAULT);
}

std::filesystem::path NewFilePath(const std::filesystem::path& aFolder)
{
    const std::time_t now = std::time(nullptr);
    std::tm local{};
    localtime_s(&local, &now);
    wchar_t name[64];
    std::wcsftime(name, std::size(name), L"game-%Y-%m-%d_%H-%M-%S.wav", &local);
    return aFolder / name;
}

class Recorder
{
public:
    explicit Recorder(std::filesystem::path aFolder) : m_folder(std::move(aFolder))
    {
    }

    bool Recording() const
    {
        return m_recording;
    }

    bool Start()
    {
        if (!m_loopback.Open())
        {
            std::printf("Couldn't open the output to record it.\n");
            return false;
        }
        m_path = NewFilePath(m_folder);
        if (!m_wav.Open(m_path, 2, m_loopback.Rate()))
        {
            std::printf("Couldn't create %ls.\n", m_path.c_str());
            m_loopback.Close();
            return false;
        }
        m_recording = true;
        m_lastSizesMs = GetTickCount64();
        std::printf("Recording to %ls\n", m_path.c_str());
        return true;
    }

    // Throws away what has arrived so far, such as the start beeps.
    void Discard()
    {
        m_block.clear();
        if (m_recording)
        {
            m_loopback.Read(m_block);
        }
    }

    // Call often: takes in what has arrived since.
    void Pump()
    {
        if (!m_recording)
        {
            return;
        }
        m_block.clear();
        if (!m_loopback.Read(m_block))
        {
            std::printf("The output went away.\n");
            Stop();
            return;
        }
        m_wav.Write(m_block);
        if (GetTickCount64() - m_lastSizesMs >= 1000)
        {
            m_lastSizesMs = GetTickCount64();
            m_wav.WriteSizes();
        }
    }

    void Stop()
    {
        if (!m_recording)
        {
            return;
        }
        m_block.clear();
        m_loopback.Read(m_block);
        m_wav.Write(m_block);
        const double seconds = m_wav.Seconds(m_loopback.Rate());
        m_wav.Close();
        m_loopback.Close();
        m_recording = false;
        std::printf("Saved %.1f s to %ls\n", seconds, m_path.c_str());
    }

private:
    std::filesystem::path m_folder;
    std::filesystem::path m_path;
    Loopback m_loopback;
    WavWriter m_wav;
    std::vector<float> m_block;
    ULONGLONG m_lastSizesMs = 0;
    bool m_recording = false;
};
} // namespace

int wmain(int aCount, wchar_t** aArguments)
{
    double testSeconds = 0.0;
    std::filesystem::path folder = L"recordings";
    for (int i = 1; i < aCount; ++i)
    {
        if (std::wcscmp(aArguments[i], L"--test") == 0 && i + 1 < aCount)
        {
            testSeconds = _wtof(aArguments[++i]);
        }
        else
        {
            folder = aArguments[i];
        }
    }
    std::error_code error;
    std::filesystem::create_directories(folder, error);
    folder = std::filesystem::absolute(folder, error);

    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    SetConsoleCtrlHandler(OnConsoleClose, TRUE);
    Recorder recorder(folder);

    if (testSeconds > 0.0)
    {
        if (!recorder.Start())
        {
            return 1;
        }
        const ULONGLONG until = GetTickCount64() + static_cast<ULONGLONG>(testSeconds * 1000.0);
        while (GetTickCount64() < until && !g_quit.load())
        {
            recorder.Pump();
            Sleep(10);
        }
        recorder.Stop();
        return 0;
    }

    if (!RegisterHotKey(nullptr, kHotkeyId, MOD_NOREPEAT, VK_PRIOR))
    {
        std::printf("Another program already uses Page Up as a hotkey, so this can't.\n");
        return 1;
    }
    const std::vector<uint8_t> startBeeps = MakeBeeps(660.0, 990.0);
    const std::vector<uint8_t> stopBeeps = MakeBeeps(990.0, 660.0);
    const std::vector<uint8_t> failBeeps = MakeBeeps(330.0, 330.0);
    std::printf("Page Up starts and stops recording what you hear, into %ls\n", folder.c_str());
    std::printf("Rising beeps: recording. Falling beeps: stopped. Two low beeps: it couldn't record. Close this window to quit.\n");

    while (!g_quit.load())
    {
        MSG message;
        while (PeekMessageW(&message, nullptr, WM_HOTKEY, WM_HOTKEY, PM_REMOVE))
        {
            if (message.wParam != kHotkeyId)
            {
                continue;
            }
            if (recorder.Recording())
            {
                recorder.Stop();
                PlayBeeps(stopBeeps);
            }
            else if (recorder.Start())
            {
                PlayBeeps(startBeeps);
                Sleep(kAfterBeepMs);
                recorder.Discard();
            }
            else
            {
                PlayBeeps(failBeeps);
            }
        }
        recorder.Pump();
        Sleep(10);
    }
    recorder.Stop();
    UnregisterHotKey(nullptr, kHotkeyId);
    return 0;
}
