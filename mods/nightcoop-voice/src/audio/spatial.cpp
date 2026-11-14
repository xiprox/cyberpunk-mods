#include "audio/spatial.hpp"

#include "audio/dsp.hpp"

#include <cmath>

namespace nv
{
namespace
{
constexpr float kOpenCutoffHz = 16000.f;
constexpr float kFarCutoffRatio = 0.28f;  // by kDullestAtMeters a voice has lost the air above about 4.5 kHz
constexpr float kDullestAtMeters = 40.f;  // apart from the far limit, so moving that doesn't change how voices sound nearer in

// Speech really loses about 6 dB per doubling of distance, which spends most of the drop in the first few metres and left 15 m closer
// to faint than to next to someone (user). Voices follow a softer bend down to this level at this distance, then fade to silence at the
// far limit. How much it bends is g_liveTuning.falloffBend.
constexpr float kFaintMeters = 40.f;
constexpr float kFaintDb = 20.6f;
constexpr float kFadeFrom = 0.8f;         // of the far limit
// How far past the radio's cut-off range it takes for a partner's radio to come back. At 3 m, stairs and floors in a building kept
// switching it (2026-11-09 log), so walking about near the edge must not.
constexpr float kRadioBackPastMeters = 10.f;

// At full occlusion, thick walls. A closed door or a thin wall comes to about 10 dB and 1.5 kHz.
constexpr float kWallCutoffHz = 450.f;
constexpr float kWallLossDb = 18.f;
constexpr float kWallMuffleCurve = 0.7f;  // treble goes sooner than level, as it does through a real wall

// A way round: sound bends around a corner, but treble bends badly. Each corner costs some of both.
constexpr float kBendGain = 0.7f;         // about -3 dB
constexpr float kBendCutoffRatio = 0.45f;
constexpr float kPathDoorGain = 0.32f;    // about -10 dB, like a closed door on the straight line
constexpr float kPathDoorCutoffRatio = 0.25f;
constexpr float kPathOpenOcclusion = 3.f; // with hardly any wall in the way the straight line carries it all

// Behind you a voice loses treble, which is the cue that tells back from front.
constexpr float kBehindCutoffLoss = 0.6f;
constexpr float kBehindGainLoss = 0.16f;

constexpr float kPanWidth = 0.85f;        // speakers: keeps some of the voice in the far ear
constexpr float kPanCloseMeters = 0.4f;

// Headphones: a sphere for a head. The level difference is modest because the delay and the treble do most of the work.
constexpr float kHeadWidth = 0.6f;
constexpr float kHeadRadiusMeters = 0.0875f;
constexpr float kSpeedOfSound = 343.f;
constexpr float kShadowHz = 1800.f;       // the far ear's treble limit with the talker straight to one side

constexpr float kCabinReachMeters = 5.f;  // a car's cabin silences everything past this
constexpr float kCabinGain = 0.45f;
constexpr float kCabinCutoffHz = 500.f;

// A room's sound stays about as loud wherever the talker stands in it, while open air thins it out like the voice itself.
constexpr float kRoomKeepsLevel = 0.7f;

// Through walls, the room the talker's in comes along. Across a clear line you're both in the same space, so this stays out
// of it, or a voice in your own room would get two tails.
constexpr float kTheirRoomOcclusion = 2.f;

// A voice is brightest in front of the mouth. With their back turned it loses treble first and some level. Right beside
// someone, which way they face hardly matters.
constexpr float kFacingCutoffRatio = 0.3f;
constexpr float kFacingGainLoss = 0.35f;  // about -4 dB
constexpr float kFacingFullMeters = 1.f;

// Underwater, voices from above barely get through, and there's no telling where they're from: sound moves too fast in
// water for the ears to compare.
constexpr float kUnderwaterGain = 0.12f;  // about -18 dB
constexpr float kUnderwaterCutoffHz = 350.f;
constexpr float kUnderwaterSide = 0.25f;

// Slow motion: dull and roomy, whatever kind it is.
constexpr float kSlowCutoffRatio = 0.2f;
constexpr float kSlowSend = 1.5f;
constexpr float kSlowFromSpeed = 0.9f;    // barely slower than this isn't felt
constexpr float kSlowFullSpeed = 0.35f;
constexpr float kStoppedSpeed = 0.005f;

// Seconds for each change from none of it to all of it. The rays move walls in steps a fifth of a second apart, so these
// are what make that continuous. Slow motion hits at once and fades, and going under is quicker than coming back up.
constexpr float kCabinSeconds = 1.f;
constexpr float kWallSeconds = 0.5f;
constexpr float kWaterInSeconds = 0.25f;
constexpr float kWaterOutSeconds = 0.4f;
constexpr float kSlowInSeconds = 0.2f;
constexpr float kSlowOutSeconds = 0.8f;
constexpr float kPathInSeconds = 0.3f;
constexpr float kPathOutSeconds = 0.5f;
constexpr float kPathGlideSeconds = 0.3f;
constexpr double kEaseSnapAfterMs = 2000.0;

float Dot(const Vec3& aLeft, const Vec3& aRight)
{
    return aLeft.x * aRight.x + aLeft.y * aRight.y + aLeft.z * aRight.z;
}

Vec3 Between(const Vec3& aFrom, const Vec3& aTo)
{
    return {aTo.x - aFrom.x, aTo.y - aFrom.y, aTo.z - aFrom.z};
}

// Turns a vector one metre long and returns how long it was.
float Normalize(Vec3& aVector)
{
    const float length = std::sqrt(Dot(aVector, aVector));
    if (length > 0.001f)
    {
        aVector.x /= length;
        aVector.y /= length;
        aVector.z /= length;
    }
    return length;
}

// Between two frequencies the way ears judge them, by ratio.
float BlendHz(float aFrom, float aTo, float aAmount)
{
    return std::pow(aFrom, 1.f - aAmount) * std::pow(aTo, aAmount);
}

float MoveToward(float aValue, float aTarget, float aElapsedSeconds, float aFullChangeSeconds)
{
    const float step = aElapsedSeconds / aFullChangeSeconds;
    return aValue + std::clamp(aTarget - aValue, -step, step);
}

float DistanceGain(float aDistance, float aNear, float aFar)
{
    return RolloffGain(aDistance, aNear) * FarFade(aDistance, aNear, aFar);
}

float DistanceCutoff(float aDistance, float aNear)
{
    return kOpenCutoffHz * std::pow(kFarCutoffRatio, Clamp01((aDistance - aNear) / std::max(kDullestAtMeters - aNear, 0.1f)));
}

// 0 they face you .. 1 their back is turned. aToTalker runs from the listener to the talker, one metre long.
float TurnedAway(const SpatialInput& aInput, const Vec3& aToTalker, float aDistance)
{
    const float length = std::sqrt(Dot(aInput.talkerForward, aInput.talkerForward));
    if (length < 0.1f)
    {
        return 0.f;
    }
    const float along = Dot(aInput.talkerForward, aToTalker) / length;
    return Clamp01((1.f + along) * 0.5f) * Clamp01(aDistance / kFacingFullMeters) * (1.f - Clamp01(aInput.sharedCabin));
}
} // namespace

void TalkerEase::Update(int aCabin, float aOcclusion, double aNowMs)
{
    const float shared = aCabin == CabinShared ? 1.f : 0.f;
    const float separated = aCabin == CabinSeparated ? 1.f : 0.f;
    const double elapsedMs = aNowMs - m_lastMs;
    if (!m_started || elapsedMs > kEaseSnapAfterMs)
    {
        m_shared = shared;
        m_separated = separated;
        m_occlusion = aOcclusion;
    }
    else
    {
        const float seconds = static_cast<float>(std::max(elapsedMs, 0.0) / 1000.0);
        m_shared = MoveToward(m_shared, shared, seconds, kCabinSeconds);
        m_separated = MoveToward(m_separated, separated, seconds, kCabinSeconds);
        m_occlusion = MoveToward(m_occlusion, aOcclusion, seconds, kWallSeconds);
    }
    m_started = true;
    m_lastMs = aNowMs;
}

void PathEase::Update(bool aFound, const Vec3& aArrival, float aMeters, float aBends, float aDoors, double aNowMs)
{
    const double elapsedMs = aNowMs - m_lastMs;
    const bool snap = !m_started || elapsedMs > kEaseSnapAfterMs;
    const float seconds = snap ? 0.f : static_cast<float>(std::max(elapsedMs, 0.0) / 1000.0);
    m_started = true;
    m_lastMs = aNowMs;

    if (snap)
    {
        m_amount = aFound ? 1.f : 0.f;
    }
    else
    {
        m_amount = MoveToward(m_amount, aFound ? 1.f : 0.f, seconds, aFound ? kPathInSeconds : kPathOutSeconds);
    }
    if (!aFound)
    {
        return; // keeps the last way round while it fades, so the voice doesn't jump as it goes
    }
    if (snap || m_amount <= seconds / kPathInSeconds)
    {
        // Nothing was coming this way, so nobody hears it arrive somewhere new.
        m_arrival = aArrival;
        m_meters = aMeters;
        m_bends = aBends;
        m_doors = aDoors;
        return;
    }
    const float glide = Clamp01(seconds / kPathGlideSeconds);
    m_arrival.x += (aArrival.x - m_arrival.x) * glide;
    m_arrival.y += (aArrival.y - m_arrival.y) * glide;
    m_arrival.z += (aArrival.z - m_arrival.z) * glide;
    m_meters += (aMeters - m_meters) * glide;
    m_bends += (aBends - m_bends) * glide;
    m_doors += (aDoors - m_doors) * glide;
}

void ListenerEase::Update(bool aUnderwater, float aSlowMotion, double aNowMs, bool aInCar)
{
    const float water = aUnderwater ? 1.f : 0.f;
    const float car = aInCar ? 1.f : 0.f;
    const double elapsedMs = aNowMs - m_lastMs;
    if (!m_started || elapsedMs > kEaseSnapAfterMs)
    {
        m_underwater = water;
        m_slowMotion = aSlowMotion;
        m_inCar = car;
    }
    else
    {
        const float seconds = static_cast<float>(std::max(elapsedMs, 0.0) / 1000.0);
        m_underwater = MoveToward(m_underwater, water, seconds, water > m_underwater ? kWaterInSeconds : kWaterOutSeconds);
        m_slowMotion = MoveToward(m_slowMotion, aSlowMotion, seconds, aSlowMotion > m_slowMotion ? kSlowInSeconds : kSlowOutSeconds);
        m_inCar = MoveToward(m_inCar, car, seconds, kCabinSeconds);
    }
    m_started = true;
    m_lastMs = aNowMs;
}

float SlowMotionFromWorldSpeed(float aWorldSpeed)
{
    if (aWorldSpeed < kStoppedSpeed)
    {
        return 0.f;
    }
    return Clamp01((kSlowFromSpeed - aWorldSpeed) / (kSlowFromSpeed - kSlowFullSpeed));
}

float RolloffGain(float aDistance, float aNearMeters)
{
    const float along = std::max(aDistance - aNearMeters, 0.f) / std::max(kFaintMeters - aNearMeters, 0.1f);
    return std::pow(10.f, -kFaintDb * std::pow(along, g_liveTuning.falloffBend.load()) / 20.f);
}

float FarFade(float aDistance, float aNearMeters, float aFarMeters)
{
    const float fadeStart = std::max(aFarMeters * kFadeFrom, aNearMeters);
    return Clamp01((aFarMeters - aDistance) / std::max(aFarMeters - fadeStart, 0.1f));
}

EarGains EarsFor(float aSide, bool aHeadphones)
{
    EarGains ears;
    if (!aHeadphones)
    {
        const float pan = aSide * kPanWidth;
        // Equal power, scaled so a voice straight ahead plays at full gain in both ears.
        ears.left = std::sqrt(1.f - pan);
        ears.right = std::sqrt(1.f + pan);
        return ears;
    }
    const float amount = std::fabs(aSide);
    const float closer = std::sqrt(1.f + kHeadWidth * amount);
    const float further = std::sqrt(1.f - kHeadWidth * amount);
    // Woodworth's formula for the extra path around a sphere.
    const float lag = (kHeadRadiusMeters / kSpeedOfSound) * (std::asin(amount) + amount) * kRate;
    if (aSide >= 0.f)
    {
        ears.right = closer;
        ears.left = further;
        ears.lagLeft = lag;
    }
    else
    {
        ears.left = closer;
        ears.right = further;
        ears.lagRight = lag;
    }
    return ears;
}

bool ShouldSendNearby(float aDistance, float aSeparatedCabin, float aFarMeters)
{
    if (aSeparatedCabin >= 1.f && aDistance >= kCabinReachMeters)
    {
        return false;
    }
    return aDistance < aFarMeters;
}

bool RadioCutWhenClose(bool aWasCut, float aDistance, float aRangeMeters, bool aApartInVehicles, bool aHeadsetOn)
{
    if (aRangeMeters <= 0.f || aApartInVehicles || aHeadsetOn)
    {
        return false;
    }
    return aDistance < (aWasCut ? RadioBackPastMeters(aRangeMeters) : aRangeMeters);
}

float RadioBackPastMeters(float aRangeMeters)
{
    return aRangeMeters + kRadioBackPastMeters;
}

bool RadioCut(bool aWasCut, float aDistance, float aRangeMeters, bool aApartInVehicles, bool aSharedVehicle, bool aKept,
              bool aHeadsetOn)
{
    return (!aKept || aSharedVehicle) && RadioCutWhenClose(aWasCut, aDistance, aRangeMeters, aApartInVehicles, aHeadsetOn);
}

bool RadioKeep::Update(uint8_t aSwitchOns, float aDistance, float aRangeMeters, double aNowMs)
{
    const bool wasKept = m_kept;
    const bool withinEdge = aDistance < RadioBackPastMeters(aRangeMeters);
    if (!m_known)
    {
        m_known = true;
        m_switchOns = aSwitchOns;
    }
    else if (aSwitchOns != m_switchOns)
    {
        m_switchOns = aSwitchOns;
        if (withinEdge)
        {
            m_kept = true;
            m_apartSinceMs = -1.0;
        }
    }
    if (m_kept)
    {
        if (withinEdge)
        {
            m_apartSinceMs = -1.0;
        }
        else if (m_apartSinceMs < 0.0)
        {
            m_apartSinceMs = aNowMs;
        }
        else if (aNowMs - m_apartSinceMs >= kApartMs)
        {
            m_kept = false;
            m_apartSinceMs = -1.0;
        }
    }
    m_changed = m_kept == wasKept ? 0 : (m_kept ? 1 : -1);
    return m_kept;
}

SpatialOutput ComputeSpatial(const SpatialInput& aInput)
{
    Vec3 toTalker = Between(aInput.listenerPosition, aInput.talkerPosition);
    const float distance = Normalize(toTalker);

    const float nearMeters = std::max(aInput.nearMeters, 0.1f);
    const float farMeters = std::max(aInput.farMeters, nearMeters + 0.1f);
    const float occlusion = Clamp01(aInput.occlusion);

    // The straight line, through whatever's in the way.
    const float straightCarried = DistanceGain(distance, nearMeters, farMeters);
    const float straightGain = straightCarried * std::pow(10.f, -kWallLossDb * occlusion / 20.f);
    const float muffle = std::pow(occlusion, kWallMuffleCurve);
    const float straightCutoff = BlendHz(DistanceCutoff(distance, nearMeters), kWallCutoffHz, muffle);

    float gain = straightGain;
    float cutoff = straightCutoff;
    float carried = straightCarried;
    Vec3 heardFrom = toTalker;
    float roundShare = 0.f;

    // And the way round, if there is one. Sound takes both, so what's heard is their sum, and it seems to come from
    // whichever carries more. That's what stops it flipping when the two are about equally loud.
    const float pathAmount = Clamp01(aInput.pathAmount) * Clamp01(occlusion * kPathOpenOcclusion);
    if (pathAmount > 0.f)
    {
        const float pathMeters = std::max(aInput.pathMeters, distance);
        const float bends = std::max(aInput.pathBends, 0.f);
        const float doors = std::max(aInput.pathDoors, 0.f);
        const float roundCarried = DistanceGain(pathMeters, nearMeters, farMeters);
        const float roundGain = roundCarried * std::pow(kBendGain, bends) * std::pow(kPathDoorGain, doors);
        const float roundCutoff = std::max(DistanceCutoff(pathMeters, nearMeters) * std::pow(kBendCutoffRatio, bends) *
                                               std::pow(kPathDoorCutoffRatio, doors),
                                           kWallCutoffHz);
        const float straightPower = straightGain * straightGain;
        const float roundPower = roundGain * roundGain * pathAmount;
        const float totalPower = straightPower + roundPower;
        if (totalPower > 1e-9f)
        {
            roundShare = roundPower / totalPower;
            gain = std::sqrt(totalPower);
            cutoff = BlendHz(straightCutoff, roundCutoff, roundShare);
            carried = straightCarried + (roundCarried - straightCarried) * roundShare;

            Vec3 toArrival = Between(aInput.listenerPosition, aInput.pathArrival);
            Normalize(toArrival);
            Vec3 blended{toTalker.x + (toArrival.x - toTalker.x) * roundShare, toTalker.y + (toArrival.y - toTalker.y) * roundShare,
                         toTalker.z + (toArrival.z - toTalker.z) * roundShare};
            // Directly opposite ways round leave nothing to blend, so it stays with whichever is stronger.
            if (Normalize(blended) > 0.05f)
            {
                heardFrom = blended;
            }
            else if (roundShare > 0.5f)
            {
                heardFrom = toArrival;
            }
        }
    }

    // What walls and bends took, which the room's sound suffers too. Distance is the part it can keep.
    const float taken = carried > 1e-4f ? std::min(gain / carried, 1.f) : 0.f;
    const float slow = Clamp01(aInput.slowMotion);
    const float enclosure = Clamp01(aInput.enclosure + (1.f - Clamp01(aInput.enclosure)) * slow);
    float send = std::pow(carried, 1.f - kRoomKeepsLevel * enclosure) * taken;

    // Sitting together: clean, whatever the raycasts hit, and no room around it.
    const float shared = Clamp01(aInput.sharedCabin);
    gain += (1.f - gain) * shared;
    cutoff = BlendHz(cutoff, kOpenCutoffHz, shared);
    send *= 1.f - shared;

    // The room hears the voice before it's dulled by where the listener's head points or which way the talker faces.
    float roomCutoff = cutoff;

    const float behind = std::max(0.f, -Dot(heardFrom, aInput.listenerForward));
    cutoff *= 1.f - kBehindCutoffLoss * behind;
    gain *= 1.f - kBehindGainLoss * behind;

    const float separated = Clamp01(aInput.separatedCabin);
    gain *= 1.f + (kCabinGain * Clamp01(1.f - distance / kCabinReachMeters) - 1.f) * separated;
    cutoff = BlendHz(cutoff, std::min(cutoff, kCabinCutoffHz), separated);
    roomCutoff = BlendHz(roomCutoff, std::min(roomCutoff, kCabinCutoffHz), separated);
    send *= 1.f - separated;

    float side = std::clamp(Dot(heardFrom, aInput.listenerRight), -1.f, 1.f);
    if (distance < kPanCloseMeters)
    {
        side *= distance / kPanCloseMeters;
    }

    SpatialOutput output;
    output.audible = ShouldSendNearby(distance, separated, farMeters);

    // Coming round a corner, what the talker's mouth points at matters less.
    output.turnedAway = TurnedAway(aInput, toTalker, distance) * (1.f - roundShare);
    cutoff *= std::pow(kFacingCutoffRatio, output.turnedAway);

    cutoff *= std::pow(kSlowCutoffRatio, slow);
    roomCutoff *= std::pow(kSlowCutoffRatio, slow);
    send *= 1.f + kSlowSend * slow;

    const float water = Clamp01(aInput.underwater);
    gain *= 1.f + (kUnderwaterGain - 1.f) * water;
    cutoff = BlendHz(cutoff, std::min(cutoff, kUnderwaterCutoffHz), water);
    roomCutoff = BlendHz(roomCutoff, std::min(roomCutoff, kUnderwaterCutoffHz), water);
    send *= 1.f - water;
    side *= 1.f + (kUnderwaterSide - 1.f) * water;

    output.lowpassHz = cutoff;
    output.reverbLowpassHz = roomCutoff;
    output.reverbSend = send;
    output.theirRoom = Clamp01(occlusion * kTheirRoomOcclusion) * (1.f - shared) * (1.f - separated) * (1.f - water);
    // Turning away takes the direct sound, not what the room gives back.
    gain *= 1.f - kFacingGainLoss * output.turnedAway;

    const EarGains ears = EarsFor(side, aInput.headphones);
    output.gainLeft = gain * ears.left;
    output.gainRight = gain * ears.right;
    output.delayLeft = ears.lagLeft;
    output.delayRight = ears.lagRight;
    if (aInput.headphones)
    {
        const float shadow = SpatialOutput::kNoShadowHz * std::pow(kShadowHz / SpatialOutput::kNoShadowHz, std::fabs(side));
        (side >= 0.f ? output.shadowLeftHz : output.shadowRightHz) = shadow;
    }
    return output;
}
} // namespace nv
