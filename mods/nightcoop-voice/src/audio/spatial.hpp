// How a nearby talker should sound, from where everyone stands. No state, so the test program can check every rule.
#pragma once

#include "core/common.hpp"

namespace nv
{
enum Cabin : int
{
    CabinNone = 0,      // nobody's cabin is between us
    CabinShared = 1,    // we sit in the same vehicle
    CabinSeparated = 2, // one of us is inside a car the other isn't in
};

struct SpatialInput
{
    Vec3 listenerPosition;
    Vec3 listenerForward;
    Vec3 listenerRight;
    Vec3 talkerPosition;
    Vec3 talkerForward;    // which way their body faces; all zeros if that isn't known
    float occlusion = 0.f; // 0 clear line .. 1 thick walls between us
    float sharedCabin = 0.f;    // 1 we sit in the same vehicle; in between while someone gets in or out
    float separatedCabin = 0.f; // 1 one of us is inside a car the other isn't in; likewise
    // The same for everyone on purpose: players hear distance alike. To change how far voices carry, change these for
    // everyone.
    float nearMeters = 2.f;
    float farMeters = 50.f; // and kFarMeters in acoustics.cpp
    bool headphones = true; // a head model for the two ears; on speakers a plain pan works better
    float underwater = 0.f;   // the listener: 0 in the air .. 1 diving
    float slowMotion = 0.f;   // 0 .. 1, from SlowMotionFromWorldSpeed
    float enclosure = 0.5f;   // around the listener: 0 open air .. 1 closed in. A room carries a voice; open air doesn't.

    // A way round the walls, if one is known. It adds to what comes through them.
    float pathAmount = 0.f;   // 0 none .. 1 fully known; in between while one is found or lost
    Vec3 pathArrival;         // the first bend the listener can see, which is where the voice seems to come from
    float pathMeters = 0.f;   // how far the sound travels along it
    float pathBends = 0.f;
    float pathDoors = 0.f;    // closed doors on the way
};

struct SpatialOutput
{
    float gainLeft = 0.f;
    float gainRight = 0.f;
    float lowpassHz = 16000.f;     // both ears: distance, walls, behind you, which way they face
    float reverbSend = 0.f;        // into the listener's room
    float reverbLowpassHz = 16000.f; // what the room hears: distance and walls, but not which way anyone faces
    float theirRoom = 0.f;         // 0 .. 1, how much of the talker's own room comes along with them
    float delayLeft = 0.f;         // samples: sound reaches the far ear a moment later
    float delayRight = 0.f;
    float shadowLeftHz = kNoShadowHz; // the head blocks treble from the far ear
    float shadowRightHz = kNoShadowHz;
    float turnedAway = 0.f;        // 0 the talker faces the listener .. 1 their back is turned. For the log.
    bool audible = false;          // whether the talker should send to this listener, from ShouldSendNearby

    static constexpr float kNoShadowHz = 20000.f;
};

SpatialOutput ComputeSpatial(const SpatialInput& aInput);

// How a voice falls off over distance, before any fade at the far limit. Bounces use this too: an echo down a tunnel can
// come from further than a voice is otherwise heard.
float RolloffGain(float aDistance, float aNearMeters);

// How much of a sound straight to one side reaches each ear, for side -1 (left) .. 1 (right). In headphones the far ear also
// hears it later; on speakers it's a plain pan.
struct EarGains
{
    float left = 1.f;
    float right = 1.f;
    float lagLeft = 0.f;  // samples
    float lagRight = 0.f;
};
EarGains EarsFor(float aSide, bool aHeadphones);

// 1 within hearing .. 0 at the far limit.
float FarFade(float aDistance, float aNearMeters, float aFarMeters);

// Whether a talker at this straight-line distance should send their nearby voice. Both players do this sum about each
// other, and walls, corners and which way anyone faces all come out differently on each machine, so it uses none of them:
// no way round is ever shorter than the straight line, so this never stops a voice someone could hear.
bool ShouldSendNearby(float aDistance, float aSeparatedCabin, float aFarMeters);

// Whether a partner's radio stops playing here because you hear them in the air instead. Each player works this out for themselves and
// only for that partner, whose radio still reaches everyone else. aWasCut holds it a little further out, so the edge doesn't flicker.
// Distance only, so it's predictable: walls and rooms don't count. In separate vehicles the distance keeps changing, so the radio
// stays. Neither is it cut with the Headset mod on in any mode: wearing it means wanting the radio (user, 2026-11-11), and its clamp
// swallows a shout beside you in a fight, where the radio is what gets through.
bool RadioCutWhenClose(bool aWasCut, float aDistance, float aRangeMeters, bool aApartInVehicles, bool aHeadsetOn);

// The radio's range edge, past which a cut partner comes back on it: aRangeMeters and a margin.
float RadioBackPastMeters(float aRangeMeters);

// All told, whether a partner's radio is cut here: by RadioCutWhenClose, unless they switched it on close by (aKept, from
// RadioKeep). In a vehicle we share that doesn't count: riders hear each other clean, so the radio would only play them
// twice (user, 2026-11-14). The Headset mod still keeps it, since its noise cancelling or its clamp takes the voice beside
// you, and the radio is then the intercom.
bool RadioCut(bool aWasCut, float aDistance, float aRangeMeters, bool aApartInVehicles, bool aSharedVehicle, bool aKept,
              bool aHeadsetOn);

// A partner who switches their radio on close to you means to be heard on it, so the cut leaves them on the radio (user, 2026-11-11):
// the cut is for a radio left on from afar, and switching on is the only thing that says otherwise. It holds until you've been past
// the range edge for kRadioKeptApartMs on end, so a dash across a fight doesn't end it but going separate ways does. aSwitchOns is how
// many times they've switched it on, as their presence counts it: only a change matters, and the first one seen is where it starts.
class RadioKeep
{
public:
    static constexpr double kApartMs = 30000.0;

    // True while they stay on the radio here, whatever the cut says.
    bool Update(uint8_t aSwitchOns, float aDistance, float aRangeMeters, double aNowMs);

    // What the last Update changed, for the log: +1 kept from now, -1 no longer, 0 nothing.
    int Changed() const
    {
        return m_changed;
    }

private:
    bool m_known = false;
    uint8_t m_switchOns = 0;
    bool m_kept = false;
    double m_apartSinceMs = -1.0;
    int m_changed = 0;
};

// How much slow motion the world's speed amounts to, 0 .. 1. The game reports 0 for loads and a stopped world, which isn't
// slow motion: there's nothing to feel slowed.
float SlowMotionFromWorldSpeed(float aWorldSpeed);

// Muffling takes time to change: getting out of a car isn't a switch. This eases what can muffle one talker. The first
// update, or one after a long gap such as a load, goes straight to the new state, since nobody heard the change.
class TalkerEase
{
public:
    void Update(int aCabin, float aOcclusion, double aNowMs);

    float SharedCabin() const
    {
        return m_shared;
    }
    float SeparatedCabin() const
    {
        return m_separated;
    }
    float Occlusion() const
    {
        return m_occlusion;
    }

private:
    bool m_started = false;
    double m_lastMs = 0.0;
    float m_shared = 0.f;
    float m_separated = 0.f;
    float m_occlusion = 0.f;
};

// A way round comes and goes, and its first bend jumps as the search finds better ones. What's heard glides.
class PathEase
{
public:
    void Update(bool aFound, const Vec3& aArrival, float aMeters, float aBends, float aDoors, double aNowMs);

    float Amount() const
    {
        return m_amount;
    }
    const Vec3& Arrival() const
    {
        return m_arrival;
    }
    float Meters() const
    {
        return m_meters;
    }
    float Bends() const
    {
        return m_bends;
    }
    float Doors() const
    {
        return m_doors;
    }

private:
    bool m_started = false;
    double m_lastMs = 0.0;
    float m_amount = 0.f;
    Vec3 m_arrival;
    float m_meters = 0.f;
    float m_bends = 0.f;
    float m_doors = 0.f;
};

// The same for what the listener's own state does to everything they hear.
class ListenerEase
{
public:
    void Update(bool aUnderwater, float aSlowMotion, double aNowMs, bool aInCar = false);

    float Underwater() const
    {
        return m_underwater;
    }
    float SlowMotion() const
    {
        return m_slowMotion;
    }
    float InCar() const
    {
        return m_inCar;
    }

private:
    bool m_started = false;
    double m_lastMs = 0.0;
    float m_underwater = 0.f;
    float m_slowMotion = 0.f;
    float m_inCar = 0.f;
};
} // namespace nv
