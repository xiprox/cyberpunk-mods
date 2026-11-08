#include "audio/mic.hpp"

#include "audio/dsp.hpp"

#include <opus.h>
#include <rnnoise.h>
#include <speex/speex_echo.h>

#include <cmath>
#include <cstring>

namespace nv
{
namespace
{
constexpr int kHoldBlocks = 40;          // 400 ms: keeps the gate open between words
constexpr float kRumbleHz = 120.f;
// Level is judged here, so bass and rumble can't make a voice read louder than it sounds.
constexpr float kSpeechBandLowHz = 300.f;
constexpr float kSpeechBandHighHz = 4000.f;
constexpr float kAgcTargetDb = -20.f;    // of the speech band
constexpr float kAgcMinDb = -12.f;
constexpr float kAgcMaxDb = 30.f;
constexpr float kAgcMaxErrorDb = 6.f;
// Quick while learning a mic, then slow enough not to ride the shape of a sentence. Per dB of error per 10 ms block.
constexpr float kAgcRate = 0.008f;       // up to about 5 dB/s
constexpr float kAgcSlowRate = 0.0008f;  // up to about 0.5 dB/s
constexpr float kSpeechSmoothing = 0.03f;      // per speech block: about a third of a second of speech
constexpr float kSpeechSmoothingSlow = 0.003f; // about three seconds
constexpr int kLearningBlocks = 600;     // 6 s of speech for a mic it knows nothing about
constexpr int kRelearnBlocks = 150;      // 1.5 s for one it remembers
constexpr float kAgcFarDb = 7.f;         // this far off, over seconds of speech, something changed: learn again
constexpr float kCompressorDb = -18.f;
constexpr float kCompressorAmount = 0.667f; // 3:1 above the threshold
constexpr float kCompressorAttack = 0.00416f;  // 5 ms
constexpr float kCompressorRelease = 0.000139f; // 150 ms
constexpr float kSilenceDb = -60.f;      // below this the gate never opens, whatever the voice detector says
constexpr int kMaxOpusBytes = 480;
constexpr int kEchoFilterSamples = 9600; // 200 ms of room and buffering
constexpr float kInt16Scale = 32768.f;
} // namespace

MicProcessor::MicProcessor(PacketSink aSink)
    : m_sink(std::move(aSink))
    , m_learningBlocks(kLearningBlocks)
{
    m_rumble.SetHighpass(kRumbleHz);
    m_bandHigh.SetHighpass(kSpeechBandLowHz);
    m_bandLow.SetLowpass(kSpeechBandHighHz);
    m_denoise = rnnoise_create(nullptr);

    int error = 0;
    m_encoder = opus_encoder_create(kRate, 1, OPUS_APPLICATION_VOIP, &error);
    if (error != OPUS_OK)
    {
        Logf(LogError, "mic: Opus encoder failed: %s", opus_strerror(error));
        m_encoder = nullptr;
        return;
    }
    opus_encoder_ctl(m_encoder, OPUS_SET_BITRATE(32000));
    opus_encoder_ctl(m_encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
    opus_encoder_ctl(m_encoder, OPUS_SET_COMPLEXITY(8));
    // Each packet also carries a rough copy of the previous one, which repairs a single lost packet.
    opus_encoder_ctl(m_encoder, OPUS_SET_INBAND_FEC(1));
    opus_encoder_ctl(m_encoder, OPUS_SET_PACKET_LOSS_PERC(10));
    opus_encoder_ctl(m_encoder, OPUS_SET_DTX(0)); // the voice gate already stops the stream in silence
}

MicProcessor::~MicProcessor()
{
    if (m_denoise)
    {
        rnnoise_destroy(m_denoise);
    }
    if (m_encoder)
    {
        opus_encoder_destroy(m_encoder);
    }
    if (m_echo)
    {
        speex_echo_state_destroy(reinterpret_cast<SpeexEchoState*>(m_echo));
    }
}

void MicProcessor::Process(const float* aMic, int aCount, const float* aEchoReference)
{
    m_pending.insert(m_pending.end(), aMic, aMic + aCount);
    if (aEchoReference)
    {
        m_pendingReference.insert(m_pendingReference.end(), aEchoReference, aEchoReference + aCount);
    }
    else
    {
        m_pendingReference.clear();
    }

    size_t used = 0;
    while (m_pending.size() - used >= kBlock)
    {
        const bool haveReference = m_pendingReference.size() >= used + kBlock;
        ProcessBlock(m_pending.data() + used, haveReference ? m_pendingReference.data() + used : nullptr);
        used += kBlock;
    }
    m_pending.erase(m_pending.begin(), m_pending.begin() + static_cast<ptrdiff_t>(used));
    if (m_pendingReference.size() >= used)
    {
        m_pendingReference.erase(m_pendingReference.begin(), m_pendingReference.begin() + static_cast<ptrdiff_t>(used));
    }
}

void MicProcessor::CancelEcho(float* aBlock, const float* aReference)
{
    const bool wanted = m_echoWanted.load() && aReference;
    if (!wanted)
    {
        if (m_echo)
        {
            speex_echo_state_destroy(reinterpret_cast<SpeexEchoState*>(m_echo));
            m_echo = nullptr;
        }
        return;
    }
    if (!m_echo)
    {
        SpeexEchoState* state = speex_echo_state_init(kBlock, kEchoFilterSamples);
        int rate = kRate;
        speex_echo_ctl(state, SPEEX_ECHO_SET_SAMPLING_RATE, &rate);
        m_echo = reinterpret_cast<SpeexEchoState_*>(state);
    }

    spx_int16_t mic[kBlock];
    spx_int16_t played[kBlock];
    spx_int16_t cleaned[kBlock];
    for (int i = 0; i < kBlock; ++i)
    {
        mic[i] = static_cast<spx_int16_t>(std::clamp(aBlock[i], -1.f, 1.f) * 32767.f);
        played[i] = static_cast<spx_int16_t>(std::clamp(aReference[i], -1.f, 1.f) * 32767.f);
    }
    speex_echo_cancellation(reinterpret_cast<SpeexEchoState*>(m_echo), mic, played, cleaned);
    for (int i = 0; i < kBlock; ++i)
    {
        aBlock[i] = static_cast<float>(cleaned[i]) / 32768.f;
    }
}

void MicProcessor::ProcessBlock(float* aBlock, const float* aReference)
{
    float scaled[kBlock];
    float denoised[kBlock];

    CancelEcho(aBlock, aReference);

    for (int i = 0; i < kBlock; ++i)
    {
        aBlock[i] = m_rumble.Process(aBlock[i]);
        scaled[i] = aBlock[i] * kInt16Scale;
    }
    const float voiceProbability = m_denoise ? rnnoise_process_frame(m_denoise, denoised, scaled) : 1.f;
    if (m_denoise && m_noiseRemoval.load())
    {
        for (int i = 0; i < kBlock; ++i)
        {
            aBlock[i] = denoised[i] / kInt16Scale;
        }
    }

    float energy = 0.f;
    float bandEnergy = 0.f;
    for (int i = 0; i < kBlock; ++i)
    {
        energy += aBlock[i] * aBlock[i];
        const float band = m_bandLow.Process(m_bandHigh.Process(aBlock[i]));
        bandEnergy += band * band;
    }
    const float rms = std::sqrt(energy / kBlock);
    const float db = 20.f * std::log10(std::max(rms, 1e-6f));

    // The meter rises at once and falls slowly, like a level meter on a mixing desk.
    m_levelState = std::max(m_levelState * 0.9f, Clamp01((db + 60.f) / 60.f));
    m_level.store(m_levelState);

    const bool muted = m_muted.load();
    const bool voice = voiceProbability >= m_gateThreshold.load() && db > kSilenceDb;
    if (voice)
    {
        m_holdBlocks = kHoldBlocks;
    }
    else if (m_holdBlocks > 0)
    {
        --m_holdBlocks;
    }
    const bool open = m_holdBlocks > 0 && !muted;
    m_gateOpenNow.store(open);

    const float preset = m_autoGainPreset.exchange(std::numeric_limits<float>::quiet_NaN());
    if (!std::isnan(preset))
    {
        m_agcDb = std::clamp(preset, kAgcMinDb, kAgcMaxDb);
        m_autoGainReport.store(m_agcDb);
        if (preset != 0.f)
        {
            m_learningBlocks = kRelearnBlocks;
        }
    }

    // Learns only from confident speech, whatever the gate is set to: a low gate must not make it chase room noise.
    if (voiceProbability >= m_autoGainConfidence.load() && db > kSilenceDb && !muted)
    {
        if (std::fabs(m_lastErrorDb) > kAgcFarDb)
        {
            m_learningBlocks = std::max(m_learningBlocks, kRelearnBlocks);
        }
        const bool learning = m_learningBlocks > 0;
        const float smoothing = learning ? kSpeechSmoothing : kSpeechSmoothingSlow;
        const float power = bandEnergy / kBlock;
        const float fullPower = energy / kBlock;
        m_speechPower = m_speechPower <= 0.f ? power : m_speechPower + (power - m_speechPower) * smoothing;
        m_speechFullPower =
            m_speechFullPower <= 0.f ? fullPower : m_speechFullPower + (fullPower - m_speechFullPower) * smoothing;
        const float speechDb = 10.f * std::log10(std::max(m_speechPower, 1e-12f));
        const float fullDb = 10.f * std::log10(std::max(m_speechFullPower, 1e-12f));
        m_rawSpeechReport.store(fullDb);
        m_bandBelowReport.store(fullDb - speechDb);

        m_lastErrorDb = kAgcTargetDb - m_agcDb - speechDb;
        const float error = std::clamp(m_lastErrorDb, -kAgcMaxErrorDb, kAgcMaxErrorDb);
        m_agcDb = std::clamp(m_agcDb + error * (learning ? kAgcRate : kAgcSlowRate), kAgcMinDb, kAgcMaxDb);
        m_autoGainReport.store(m_agcDb);
        if (m_learningBlocks > 0)
        {
            --m_learningBlocks;
        }
    }
    const float agcTarget = std::pow(10.f, m_agcDb / 20.f);
    const float agcStep = (agcTarget - m_agcLinear) / kBlock;
    for (int i = 0; i < kBlock; ++i)
    {
        m_agcLinear += agcStep;
        aBlock[i] *= m_agcLinear;
    }
    Compress(aBlock);

    if (open)
    {
        if (m_ownVoiceSink)
        {
            m_ownVoiceSink(aBlock, kBlock);
        }
        float sent = 0.f;
        for (int i = 0; i < kBlock; ++i)
        {
            sent += aBlock[i] * aBlock[i];
        }
        sent /= kBlock;
        m_sentPower = m_sentPower <= 0.f ? sent : m_sentPower + (sent - m_sentPower) * kSpeechSmoothing;
        m_sentSpeechReport.store(10.f * std::log10(std::max(m_sentPower, 1e-12f)));
    }

    if (open && !m_wasOpen)
    {
        // The detector needs a moment to notice speech, so send the 20 ms before it did as the first packet.
        if (m_encoder)
        {
            opus_encoder_ctl(m_encoder, OPUS_RESET_STATE);
        }
        std::memcpy(m_frame, m_preroll, sizeof(m_frame));
        Encode(true);
        m_frameFill = 0;
    }

    if (open)
    {
        std::memcpy(m_frame + m_frameFill, aBlock, sizeof(float) * kBlock);
        m_frameFill += kBlock;
        if (m_frameFill == kFrame)
        {
            Encode(false);
            m_frameFill = 0;
        }
    }
    else
    {
        if (m_wasOpen && m_frameFill > 0)
        {
            std::memset(m_frame + m_frameFill, 0, sizeof(float) * static_cast<size_t>(kFrame - m_frameFill));
            Encode(false);
        }
        m_frameFill = 0;
    }
    m_wasOpen = open;

    std::memmove(m_preroll, m_preroll + kBlock, sizeof(float) * kBlock);
    std::memcpy(m_preroll + kBlock, aBlock, sizeof(float) * kBlock);
}

// Brings shouts down toward ordinary speech. The automatic gain is far too slow to catch them, and is meant to be.
void MicProcessor::Compress(float* aBlock)
{
    for (int i = 0; i < kBlock; ++i)
    {
        const float magnitude = std::fabs(aBlock[i]);
        m_compressorEnvelope +=
            (magnitude - m_compressorEnvelope) * (magnitude > m_compressorEnvelope ? kCompressorAttack : kCompressorRelease);
        const float over = 20.f * std::log10(std::max(m_compressorEnvelope, 1e-6f)) - kCompressorDb;
        const float gain = over > 0.f ? std::pow(10.f, -over * kCompressorAmount / 20.f) : 1.f;
        aBlock[i] = SoftClip(aBlock[i] * gain);
    }
}

void MicProcessor::Encode(bool aSpurt)
{
    if (!m_encoder)
    {
        return;
    }
    uint8_t packet[kMaxOpusBytes];
    const opus_int32 size = opus_encode_float(m_encoder, m_frame, kFrame, packet, kMaxOpusBytes);
    if (size > 0)
    {
        m_sink(packet, size, aSpurt);
    }
}
} // namespace nv
