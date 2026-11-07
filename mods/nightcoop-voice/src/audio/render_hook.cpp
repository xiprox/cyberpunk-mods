#include "audio/render_hook.hpp"

#include "audio/headset.hpp"
#include "core/common.hpp"

#include <windows.h>

#include <mmdeviceapi.h>

#include <audioclient.h>
#include <intrin.h>

#include <atomic>
#include <mutex>
#include <thread>

namespace nv
{
namespace
{
using InitializeFn = HRESULT(STDMETHODCALLTYPE*)(IAudioClient*, AUDCLNT_SHAREMODE, DWORD, REFERENCE_TIME, REFERENCE_TIME,
                                                 const WAVEFORMATEX*, LPCGUID);
using GetServiceFn = HRESULT(STDMETHODCALLTYPE*)(IAudioClient*, REFIID, void**);
using InitializeSharedFn = HRESULT(STDMETHODCALLTYPE*)(IAudioClient3*, DWORD, UINT32, const WAVEFORMATEX*, LPCGUID);
using GetBufferFn = HRESULT(STDMETHODCALLTYPE*)(IAudioRenderClient*, UINT32, BYTE**);
using ReleaseBufferFn = HRESULT(STDMETHODCALLTYPE*)(IAudioRenderClient*, UINT32, DWORD);

// Places in the function tables, which are fixed by the interfaces' published order.
constexpr int kInitializeSlot = 3;
constexpr int kGetServiceSlot = 14;
constexpr int kInitializeSharedSlot = 20; // IAudioClient3::InitializeSharedAudioStream
constexpr int kGetBufferSlot = 3;
constexpr int kReleaseBufferSlot = 4;
constexpr int kStreams = 16;

std::atomic<InitializeFn> g_initialize{nullptr};
std::atomic<GetServiceFn> g_getService{nullptr};
std::atomic<InitializeSharedFn> g_initializeShared{nullptr};
std::atomic<GetBufferFn> g_getBuffer{nullptr};
std::atomic<ReleaseBufferFn> g_releaseBuffer{nullptr};

thread_local bool t_own = false;

struct Stream
{
    std::atomic<void*> client{nullptr};
    std::atomic<void*> render{nullptr};
    std::atomic<bool> own{false};
    std::atomic<bool> usable{false};
    std::atomic<bool> report{false};
    std::atomic<BYTE*> buffer{nullptr};
    std::atomic<uint32_t> bufferFrames{0};
    HeadsetStream headset;
};

Stream g_streams[kStreams];
std::mutex g_setupLock;
int g_nextStream = 0;
std::atomic<uint32_t> g_seen{0};
std::atomic<uint32_t> g_used{0};
std::atomic<uint64_t> g_run{0};
std::atomic<uint64_t> g_ownBuffers{0};
double g_nsPerTick = 0.0;
HMODULE g_gameModule = nullptr;

bool Float32(const WAVEFORMATEX* aFormat)
{
    if (!aFormat || aFormat->wBitsPerSample != 32)
    {
        return false;
    }
    if (aFormat->wFormatTag == WAVE_FORMAT_IEEE_FLOAT)
    {
        return true;
    }
    if (aFormat->wFormatTag == WAVE_FORMAT_EXTENSIBLE && aFormat->cbSize >= 22)
    {
        // The sub-format's first part is the plain format number.
        return reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(aFormat)->SubFormat.Data1 == WAVE_FORMAT_IEEE_FLOAT;
    }
    return false;
}

HMODULE ModuleAt(void* aAddress)
{
    HMODULE module = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       static_cast<LPCWSTR>(aAddress), &module);
    return module;
}

std::string ModuleName(HMODULE aModule)
{
    wchar_t path[MAX_PATH] = {};
    if (!aModule || !GetModuleFileNameW(aModule, path, MAX_PATH))
    {
        return "an unknown module";
    }
    const wchar_t* name = wcsrchr(path, L'\\');
    name = name ? name + 1 : path;
    char out[MAX_PATH] = {};
    WideCharToMultiByte(CP_UTF8, 0, name, -1, out, sizeof(out), nullptr, nullptr);
    return out;
}

Stream* FindRender(void* aRender)
{
    for (Stream& stream : g_streams)
    {
        if (stream.render.load(std::memory_order_acquire) == aRender)
        {
            return &stream;
        }
    }
    return nullptr;
}

void Register(void* aClient, const WAVEFORMATEX* aFormat, DWORD aFlags, void* aCaller)
{
    const bool own = t_own;
    const bool loopback = (aFlags & AUDCLNT_STREAMFLAGS_LOOPBACK) != 0;
    std::lock_guard lock(g_setupLock);
    // The same client set up again, or a new one where a released one was: either way its old entry no longer holds.
    for (Stream& stream : g_streams)
    {
        if (stream.client.load(std::memory_order_relaxed) == aClient)
        {
            stream.render.store(nullptr, std::memory_order_release);
            stream.client.store(nullptr, std::memory_order_release);
        }
    }
    Stream* slot = nullptr;
    for (Stream& stream : g_streams)
    {
        if (!stream.client.load(std::memory_order_relaxed))
        {
            slot = &stream;
            break;
        }
    }
    if (!slot)
    {
        slot = &g_streams[g_nextStream];
        g_nextStream = (g_nextStream + 1) % kStreams;
    }
    slot->render.store(nullptr, std::memory_order_release);
    slot->buffer.store(nullptr, std::memory_order_relaxed);
    const int channels = aFormat ? aFormat->nChannels : 0;
    const int rate = aFormat ? static_cast<int>(aFormat->nSamplesPerSec) : 0;
    const bool usable = !own && !loopback && Float32(aFormat) && channels >= 1 && channels <= HeadsetStream::kMaxChannels &&
                        rate >= 8000;
    if (usable)
    {
        slot->headset.Configure(channels, rate);
    }
    const HMODULE module = ModuleAt(aCaller);
    slot->own.store(own, std::memory_order_relaxed);
    slot->usable.store(usable, std::memory_order_relaxed);
    slot->report.store(usable && module == g_gameModule, std::memory_order_relaxed);
    slot->client.store(aClient, std::memory_order_release);

    if (!own && !loopback)
    {
        g_seen.fetch_add(1);
        g_used.fetch_add(usable ? 1 : 0);
        Logf(LogInfo, "headset: a sound stream set up by %s, %d channel(s), %d Hz, %d-bit %s: %s", ModuleName(module).c_str(),
             channels, rate, aFormat ? aFormat->wBitsPerSample : 0, Float32(aFormat) ? "float" : "integer",
             usable ? "the headset can run on it" : "left alone");
    }
}

HRESULT STDMETHODCALLTYPE HookInitialize(IAudioClient* aThis, AUDCLNT_SHAREMODE aMode, DWORD aFlags, REFERENCE_TIME aBuffer,
                                         REFERENCE_TIME aPeriod, const WAVEFORMATEX* aFormat, LPCGUID aSession)
{
    const HRESULT result = g_initialize.load(std::memory_order_relaxed)(aThis, aMode, aFlags, aBuffer, aPeriod, aFormat, aSession);
    if (SUCCEEDED(result))
    {
        Register(aThis, aFormat, aFlags, _ReturnAddress());
    }
    return result;
}

HRESULT STDMETHODCALLTYPE HookInitializeShared(IAudioClient3* aThis, DWORD aFlags, UINT32 aPeriod, const WAVEFORMATEX* aFormat,
                                               LPCGUID aSession)
{
    const HRESULT result = g_initializeShared.load(std::memory_order_relaxed)(aThis, aFlags, aPeriod, aFormat, aSession);
    if (SUCCEEDED(result))
    {
        Register(aThis, aFormat, aFlags, _ReturnAddress());
    }
    return result;
}

HRESULT STDMETHODCALLTYPE HookGetService(IAudioClient* aThis, REFIID aId, void** aOut)
{
    const HRESULT result = g_getService.load(std::memory_order_relaxed)(aThis, aId, aOut);
    if (SUCCEEDED(result) && aOut && *aOut && IsEqualIID(aId, __uuidof(IAudioRenderClient)))
    {
        std::lock_guard lock(g_setupLock);
        for (Stream& stream : g_streams)
        {
            if (stream.render.load(std::memory_order_relaxed) == *aOut)
            {
                stream.render.store(nullptr, std::memory_order_release);
            }
        }
        for (Stream& stream : g_streams)
        {
            if (stream.client.load(std::memory_order_relaxed) == aThis)
            {
                stream.render.store(*aOut, std::memory_order_release);
                break;
            }
        }
    }
    return result;
}

HRESULT STDMETHODCALLTYPE HookGetBuffer(IAudioRenderClient* aThis, UINT32 aFrames, BYTE** aData)
{
    const HRESULT result = g_getBuffer.load(std::memory_order_relaxed)(aThis, aFrames, aData);
    if (SUCCEEDED(result) && aData)
    {
        if (Stream* stream = FindRender(aThis))
        {
            stream->buffer.store(*aData, std::memory_order_relaxed);
            stream->bufferFrames.store(aFrames, std::memory_order_relaxed);
        }
    }
    return result;
}

HRESULT STDMETHODCALLTYPE HookReleaseBuffer(IAudioRenderClient* aThis, UINT32 aFrames, DWORD aFlags)
{
    if (Stream* stream = FindRender(aThis))
    {
        BYTE* buffer = stream->buffer.exchange(nullptr, std::memory_order_relaxed);
        if (stream->own.load(std::memory_order_relaxed))
        {
            g_ownBuffers.fetch_add(1, std::memory_order_relaxed);
        }
        else if (stream->usable.load(std::memory_order_relaxed) && buffer && aFrames > 0 &&
                 aFrames <= stream->bufferFrames.load(std::memory_order_relaxed) && !(aFlags & AUDCLNT_BUFFERFLAGS_SILENT))
        {
            LARGE_INTEGER start;
            LARGE_INTEGER end;
            QueryPerformanceCounter(&start);
            stream->headset.Process(reinterpret_cast<float*>(buffer), aFrames, g_headset.on.load(std::memory_order_relaxed),
                                    g_headset.levelShiftDb.load(std::memory_order_relaxed),
                                    stream->report.load(std::memory_order_relaxed), NowMs());
            QueryPerformanceCounter(&end);
            g_headset.costNs.fetch_add(static_cast<uint64_t>(static_cast<double>(end.QuadPart - start.QuadPart) * g_nsPerTick),
                                       std::memory_order_relaxed);
            g_run.fetch_add(1, std::memory_order_relaxed);
        }
    }
    return g_releaseBuffer.load(std::memory_order_relaxed)(aThis, aFrames, aFlags);
}

// One slot of a shared function table: the original goes aside first, so a call arriving in between still has somewhere
// to go.
template <typename Fn>
bool Patch(void** aTable, int aSlot, Fn aHook, std::atomic<Fn>& aOriginal)
{
    void** entry = &aTable[aSlot];
    if (*entry == reinterpret_cast<void*>(aHook))
    {
        return true;
    }
    MEMORY_BASIC_INFORMATION page{};
    if (!VirtualQuery(entry, &page, sizeof(page)))
    {
        return false;
    }
    const bool executable =
        (page.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) != 0;
    DWORD old = 0;
    if (!VirtualProtect(entry, sizeof(void*), executable ? PAGE_EXECUTE_READWRITE : PAGE_READWRITE, &old))
    {
        return false;
    }
    aOriginal.store(reinterpret_cast<Fn>(*entry));
    InterlockedExchangePointer(entry, reinterpret_cast<void*>(aHook));
    VirtualProtect(entry, sizeof(void*), old, &old);
    return true;
}

template <typename T>
void Release(T*& aObject)
{
    if (aObject)
    {
        aObject->Release();
        aObject = nullptr;
    }
}

bool InstallOnThisThread(std::string& aWhy)
{
    IMMDeviceEnumerator* enumerator = nullptr;
    IMMDevice* device = nullptr;
    IAudioClient* client = nullptr;
    IAudioClient3* client3 = nullptr;
    IAudioRenderClient* render = nullptr;
    WAVEFORMATEX* mix = nullptr;
    bool ok = false;
    if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                reinterpret_cast<void**>(&enumerator))))
    {
        aWhy = "Windows' audio devices couldn't be listed";
    }
    else if (FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device)))
    {
        aWhy = "there's no output device";
    }
    else if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(&client))) ||
             FAILED(client->GetMixFormat(&mix)) ||
             FAILED(client->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 10000000, 0, mix, nullptr)) ||
             FAILED(client->GetService(__uuidof(IAudioRenderClient), reinterpret_cast<void**>(&render))))
    {
        aWhy = "a stream to find the functions on couldn't be opened";
    }
    else
    {
        void** clientTable = *reinterpret_cast<void***>(client);
        void** renderTable = *reinterpret_cast<void***>(render);
        ok = Patch(clientTable, kInitializeSlot, &HookInitialize, g_initialize) &&
             Patch(clientTable, kGetServiceSlot, &HookGetService, g_getService) &&
             Patch(renderTable, kGetBufferSlot, &HookGetBuffer, g_getBuffer) &&
             Patch(renderTable, kReleaseBufferSlot, &HookReleaseBuffer, g_releaseBuffer);
        if (!ok)
        {
            aWhy = "the functions couldn't be patched";
        }
        else if (SUCCEEDED(client->QueryInterface(__uuidof(IAudioClient3), reinterpret_cast<void**>(&client3))) && client3 &&
                 *reinterpret_cast<void***>(client3) == clientTable)
        {
            // Newer games may set up through IAudioClient3; the same table holds it further down.
            Patch(clientTable, kInitializeSharedSlot, &HookInitializeShared, g_initializeShared);
        }
    }
    Release(render);
    Release(client3);
    Release(client);
    Release(device);
    Release(enumerator);
    if (mix)
    {
        CoTaskMemFree(mix);
    }
    return ok;
}
} // namespace

bool InstallRenderHook()
{
    static std::atomic<bool> s_tried{false};
    static bool s_installed = false;
    if (s_tried.exchange(true))
    {
        return s_installed;
    }
    LARGE_INTEGER frequency;
    QueryPerformanceFrequency(&frequency);
    g_nsPerTick = 1e9 / static_cast<double>(frequency.QuadPart);
    g_gameModule = GetModuleHandleW(nullptr);

    // A thread of its own, so the caller's COM setup is never touched.
    std::string why;
    std::thread([&] {
        const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        t_own = true;
        s_installed = InstallOnThisThread(why);
        t_own = false;
        if (SUCCEEDED(com))
        {
            CoUninitialize();
        }
    }).join();

    if (s_installed)
    {
        Logf(LogInfo, "headset: watching the game's sound output");
    }
    else
    {
        Logf(LogWarn, "headset: can't reach the game's sound, since %s; the radio headset changes only voices", why.c_str());
    }
    return s_installed;
}

void SetOwnStreamsOnThisThread(bool aOwn)
{
    t_own = aOwn;
}

RenderHookCounts GetRenderHookCounts()
{
    RenderHookCounts counts;
    counts.streamsSeen = g_seen.load();
    counts.streamsUsed = g_used.load();
    counts.buffersRun = g_run.load();
    counts.buffersOwn = g_ownBuffers.load();
    return counts;
}
} // namespace nv
