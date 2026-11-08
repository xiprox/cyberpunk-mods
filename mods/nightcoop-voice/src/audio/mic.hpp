// Turns raw mic audio into Opus packets: echo removal (optional), noise removal, automatic gain, a compressor, the voice
// gate, Opus. Whatever the mic, speech leaves here at about the same level. No devices here, so the test program can feed
// it directly.
#pragma once

#include "audio/dsp.hpp"

#include <atomic>
#include <cmath>
#include <functional>
#include <limits>
#include <vector>

struct DenoiseState;
struct OpusEncoder;
struct SpeexEchoState_;

namespace nv
{
class MicProcessor
{
public:
    // aOpus lasts only for the call; aSpurt marks the first packet after the gate opened.
    using PacketSink = std::function<void(const uint8_t* aOpus, int aSize, bool aSpurt)>;

    // Your finished voice while the gate's open, a block at a time, before it's encoded. Set it before any audio flows.
    using OwnVoiceSink = std::function<void(const float* aSamples, int aCount)>;

    explicit MicProcessor(PacketSink aSink);
    ~MicProcessor();

    void SetOwnVoiceSink(OwnVoiceSink aSink)
    {
        m_ownVoiceSink = std::move(aSink);
    }

    MicProcessor(const MicProcessor&) = delete;
    MicProcessor& operator=(const MicProcessor&) = delete;

    // Mono 48 kHz, -1..1, any amount at a time. aEchoReference is what the speakers played, same length, or null.
    void Process(const float* aMic, int aCount, const float* aEchoReference = nullptr);

    // Safe from any thread.
    void SetMuted(bool aMuted)
    {
        m_muted.store(aMuted);
    }
    void SetGateThreshold(float aThreshold)
    {
        m_gateThreshold.store(aThreshold);
    }
    void SetNoiseRemoval(bool aOn)
    {
        m_noiseRemoval.store(aOn);
    }
    void SetEchoCancellation(bool aOn)
    {
        m_echoWanted.store(aOn);
    }

    // Starts the automatic gain from what it learned for this mic last time.
    void PresetAutoGain(float aDb)
    {
        m_autoGainPreset.store(aDb);
    }
    // How sure of speech the automatic gain must be before learning from it. Only the test program changes this.
    void SetAutoGainConfidence(float aConfidence)
    {
        m_autoGainConfidence.store(aConfidence);
    }

    float AutoGainDb() const
    {
        return m_autoGainReport.load();
    }
    float RawSpeechDb() const
    {
        return m_rawSpeechReport.load();
    }
    // How far the speech frequencies sit below the whole signal: a big number means lots of bass or rumble.
    float SpeechBandBelowDb() const
    {
        return m_bandBelowReport.load();
    }
    float SentSpeechDb() const
    {
        return m_sentSpeechReport.load();
    }

    float Level() const
    {
        return m_level.load(); // 0..1, smoothed, for the meter
    }
    bool GateOpen() const
    {
        return m_gateOpenNow.load();
    }

private:
    void ProcessBlock(float* aBlock, const float* aReference);
    void CancelEcho(float* aBlock, const float* aReference);
    void Compress(float* aBlock);
    void Encode(bool aSpurt);

    PacketSink m_sink;
    OwnVoiceSink m_ownVoiceSink;
    DenoiseState* m_denoise = nullptr;
    OpusEncoder* m_encoder = nullptr;
    SpeexEchoState_* m_echo = nullptr;

    std::vector<float> m_pending;
    std::vector<float> m_pendingReference;
    float m_preroll[kFrame]{};
    float m_frame[kFrame]{};
    int m_frameFill = 0;
    bool m_wasOpen = false;
    int m_holdBlocks = 0;
    float m_levelState = 0.f;
    float m_agcDb = 0.f;
    float m_agcLinear = 1.f;
    float m_speechPower = 0.f;
    float m_speechFullPower = 0.f;
    float m_lastErrorDb = 0.f;
    int m_learningBlocks = 0;
    Biquad m_rumble;
    Biquad m_bandHigh;
    Biquad m_bandLow;
    float m_sentPower = 0.f;
    float m_compressorEnvelope = 0.f;

    std::atomic<bool> m_muted{false};
    std::atomic<bool> m_noiseRemoval{true};
    std::atomic<bool> m_echoWanted{false};
    std::atomic<float> m_gateThreshold{0.6f};
    std::atomic<float> m_level{0.f};
    std::atomic<bool> m_gateOpenNow{false};
    std::atomic<float> m_autoGainConfidence{0.8f};
    std::atomic<float> m_autoGainPreset{std::numeric_limits<float>::quiet_NaN()};
    std::atomic<float> m_autoGainReport{0.f};
    std::atomic<float> m_rawSpeechReport{-100.f};
    std::atomic<float> m_bandBelowReport{0.f};
    std::atomic<float> m_sentSpeechReport{-100.f};
};
} // namespace nv
