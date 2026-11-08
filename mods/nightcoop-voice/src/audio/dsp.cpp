#include "audio/dsp.hpp"

namespace nv
{
namespace
{
// Delay lengths at 48 kHz, chosen not to share factors so the echoes don't line up: about 6 to 20 ms for a room, 21 to 77 ms
// for a big space.
constexpr std::array<size_t, 8> kSmallDelays{269, 347, 419, 509, 601, 709, 811, 947};
constexpr std::array<size_t, 8> kLargeDelays{1009, 1361, 1693, 2053, 2399, 2801, 3203, 3701};

// A big space's walls are far off, so its sound starts later.
constexpr size_t kSmallPreDelay = 96;
constexpr size_t kLargePreDelay = 960;

// How much treble each round trip keeps. Rounds come slower in a big space, but air takes more on the way.
constexpr float kSmallDamping = 0.75f;
constexpr float kLargeDamping = 0.5f;

// Scrambles a voice on its way in. The networks' first time round is only eight copies of it, which reads as somebody else
// saying the same words, so they should never get a clean one.
constexpr std::array<size_t, 4> kDiffuserSizes{211, 337, 503, 797};
constexpr float kDiffuserFeedback = 0.6f;

// How loud a room's sound is against a voice 2 m away. In a real closed room the two are about equal at that distance, but
// you don't hear it that way: ears favour what arrives first, and headphones can't do that. So well under, by ear.
constexpr float kWetOpenDb = -38.f;
constexpr float kWetClosedDb = -18.f;

constexpr float kSmallRoomMeters = 2.5f;
constexpr float kLargeRoomMeters = 10.f;

// A big space's delays only sound like a space if the sound goes round them many times. With a short decay it hardly goes
// round once, and what comes out is the voice repeated a tenth of a second later: an echo, not a room. So until a sound rings
// this long, it stays in the small network, however big the place.
constexpr float kLargeNeedsDecayFrom = 0.3f;
constexpr float kLargeNeedsDecayTo = 1.f;

// How each line is fed and heard. The two ears' patterns don't overlap, so they hear different sound from the same room.
constexpr std::array<float, 8> kInputSigns{1.f, -1.f, 1.f, -1.f, 1.f, -1.f, 1.f, -1.f};
constexpr std::array<float, 8> kLeftSigns{1.f, 1.f, -1.f, -1.f, 1.f, 1.f, -1.f, -1.f};
constexpr std::array<float, 8> kRightSigns{1.f, -1.f, 1.f, -1.f, 1.f, -1.f, 1.f, -1.f};

const float kLineScale = 1.f / std::sqrt(8.f);

// What the damping takes from the loop's energy, as measured by the test program, so the tail stays at the level asked for.
constexpr float kOutputTrim = 1.25f;

constexpr float kEasePerBlock = 0.02f;
constexpr float kDecayChangeWorthApplying = 0.005f;
constexpr float kMinDecay = 0.1f;
constexpr float kMaxDecay = 6.f;

void Build(std::array<std::vector<float>, 8>& aLines, const std::array<size_t, 8>& aDelays, float& aMeanDelay)
{
    float total = 0.f;
    for (size_t i = 0; i < aDelays.size(); ++i)
    {
        aLines[i].resize(aDelays[i]);
        total += static_cast<float>(aDelays[i]);
    }
    aMeanDelay = total / static_cast<float>(aDelays.size());
}
} // namespace

RoomReverb::RoomReverb()
{
    Build(m_small.lines, kSmallDelays, m_small.meanDelay);
    Build(m_large.lines, kLargeDelays, m_large.meanDelay);
    m_small.damping = kSmallDamping;
    m_large.damping = kLargeDamping;
    m_small.preDelay.resize(kSmallPreDelay);
    m_large.preDelay.resize(kLargePreDelay);
    for (size_t i = 0; i < kDiffuserSizes.size(); ++i)
    {
        m_diffusers[i].buffer.resize(kDiffuserSizes[i]);
    }
}

void RoomReverb::SetRoom(const RoomSound& aRoom)
{
    m_target = aRoom;
}

void RoomReverb::SetDecay(Network& aNetwork, float aDecaySeconds)
{
    for (int i = 0; i < kLines; ++i)
    {
        // -60 dB after the decay time, whichever line the sound is in.
        const float seconds = static_cast<float>(aNetwork.lines[static_cast<size_t>(i)].size()) / kRate;
        aNetwork.gains[static_cast<size_t>(i)] = std::pow(10.f, -3.f * seconds / aDecaySeconds);
    }
    // A loop that loses little holds a lot of energy. This takes that back out on the way in.
    const float meanGain = std::pow(10.f, -3.f * (aNetwork.meanDelay / kRate) / aDecaySeconds);
    aNetwork.inputGain = std::sqrt(std::max(1.f - meanGain * meanGain, 0.f));
}

void RoomReverb::Step(Network& aNetwork, float aInput, float& aLeft, float& aRight)
{
    float output[kLines];
    float sum = 0.f;
    for (int i = 0; i < kLines; ++i)
    {
        const auto line = static_cast<size_t>(i);
        output[i] = aNetwork.lines[line][aNetwork.positions[line]];
        aNetwork.damped[line] += aNetwork.damping * (output[i] - aNetwork.damped[line]);
        sum += aNetwork.damped[line];
    }
    // A Householder matrix: every line feeds every other, and no energy is lost or added by the mixing.
    const float shared = sum * 0.25f;
    for (int i = 0; i < kLines; ++i)
    {
        const auto line = static_cast<size_t>(i);
        const float fed = (aNetwork.damped[line] - shared) * aNetwork.gains[line] + aInput * kInputSigns[line] * kLineScale;
        aNetwork.lines[line][aNetwork.positions[line]] = fed;
        aNetwork.positions[line] = aNetwork.positions[line] + 1 == aNetwork.lines[line].size() ? 0 : aNetwork.positions[line] + 1;
        aLeft += output[i] * kLeftSigns[line];
        aRight += output[i] * kRightSigns[line];
    }
}

void RoomReverb::Process(const float* aSend, float* aLeft, float* aRight, int aFrames)
{
    const float enclosure = Clamp01(m_target.enclosure);
    const float targetWet = std::pow(10.f, (kWetOpenDb + (kWetClosedDb - kWetOpenDb) * enclosure + g_liveTuning.roomDb.load()) / 20.f);
    const float targetDecay = std::clamp(m_target.decaySeconds * g_liveTuning.ring.load(), kMinDecay, kMaxDecay);
    const float targetSize = std::min(Clamp01((m_target.meters - kSmallRoomMeters) / (kLargeRoomMeters - kSmallRoomMeters)),
                                      Clamp01((targetDecay - kLargeNeedsDecayFrom) / (kLargeNeedsDecayTo - kLargeNeedsDecayFrom)));

    if (m_wet <= 0.f)
    {
        // The first block: start in the room, not on the way to it.
        m_wet = targetWet;
        m_size = targetSize;
        m_decay = targetDecay;
    }
    const float startWet = m_wet;
    const float startSize = m_size;
    m_wet += (targetWet - m_wet) * kEasePerBlock;
    m_size += (targetSize - m_size) * kEasePerBlock;
    m_decay *= std::pow(targetDecay / m_decay, kEasePerBlock);
    if (std::fabs(m_decay - m_appliedDecay) > m_appliedDecay * kDecayChangeWorthApplying)
    {
        m_appliedDecay = m_decay;
        SetDecay(m_small, m_decay);
        SetDecay(m_large, m_decay);
    }

    const float frames = static_cast<float>(aFrames);
    for (int i = 0; i < aFrames; ++i)
    {
        const float progress = static_cast<float>(i) / frames;
        const float wet = startWet + (m_wet - startWet) * progress;
        const float size = startSize + (m_size - startSize) * progress;

        float input = aSend[i] * wet * kOutputTrim;
        for (Diffuser& diffuser : m_diffusers)
        {
            const float delayed = diffuser.buffer[diffuser.position];
            const float fed = input + delayed * kDiffuserFeedback;
            diffuser.buffer[diffuser.position] = fed;
            input = delayed - fed * kDiffuserFeedback;
            diffuser.position = diffuser.position + 1 == diffuser.buffer.size() ? 0 : diffuser.position + 1;
        }

        const auto delayedInto = [input](Network& aNetwork, float aShare) {
            const float out = aNetwork.preDelay[aNetwork.preDelayPosition];
            aNetwork.preDelay[aNetwork.preDelayPosition] = input * aShare * aNetwork.inputGain;
            aNetwork.preDelayPosition = aNetwork.preDelayPosition + 1 == aNetwork.preDelay.size() ? 0 : aNetwork.preDelayPosition + 1;
            return out;
        };
        // Equal power, so a room between the two isn't quieter than either.
        const float smallInput = delayedInto(m_small, std::sqrt(1.f - size));
        const float largeInput = delayedInto(m_large, std::sqrt(size));
        Step(m_small, smallInput, aLeft[i], aRight[i]);
        Step(m_large, largeInput, aLeft[i], aRight[i]);
    }
}
} // namespace nv
