// Windows audio devices, always as 48 kHz float on our side whatever the device wants. Each stream belongs to one
// thread, which must have called ComThread first.
#pragma once

#include "audio/dsp.hpp"

#include <string>
#include <vector>

struct IAudioCaptureClient;
struct IAudioClient;
struct IAudioRenderClient;

namespace nv
{
struct DeviceInfo
{
    std::string id; // empty means the system default
    std::string name;
};

// Runs on a thread of its own, so it's safe to call from the game thread.
std::vector<DeviceInfo> ListDevices(bool aCapture);

class ComThread
{
public:
    ComThread();
    ~ComThread();
};

struct StreamFormat
{
    int channels = 0;
    int rate = 0;
    bool isFloat = false;
    int bytesPerSample = 0;
};

class CaptureStream
{
public:
    ~CaptureStream();

    // aLoopback records what the output device aId plays.
    bool Open(const std::string& aId, bool aLoopback);
    void Close();
    bool IsOpen() const
    {
        return m_client != nullptr;
    }

    // Waits up to aWaitMs when nothing is ready, then appends mono samples. False means the device is gone.
    bool Read(std::vector<float>& aOut, int aWaitMs);

private:
    IAudioClient* m_client = nullptr;
    IAudioCaptureClient* m_capture = nullptr;
    void* m_event = nullptr;
    StreamFormat m_format;
    Resampler m_resampler;
};

class RenderStream
{
public:
    ~RenderStream();

    bool Open(const std::string& aId);
    void Close();
    bool IsOpen() const
    {
        return m_client != nullptr;
    }

    // How many 48 kHz frames to write now to keep the output buffer at our target. Negative means the device is gone.
    int Wanted();

    // Interleaved stereo at 48 kHz. False means the device is gone.
    bool Write(const float* aStereo, int aFrames);

    void Wait(int aMs);

private:
    IAudioClient* m_client = nullptr;
    IAudioRenderClient* m_render = nullptr;
    void* m_event = nullptr;
    StreamFormat m_format;
    unsigned int m_bufferFrames = 0;
    unsigned int m_targetFrames = 0;
    Resampler m_resamplerLeft;
    Resampler m_resamplerRight;
    std::vector<float> m_left;
    std::vector<float> m_right;
    std::vector<float> m_pendingStereo;
};
} // namespace nv
