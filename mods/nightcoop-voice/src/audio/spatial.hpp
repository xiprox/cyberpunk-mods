// How a nearby talker should sound, from where everyone stands. No state, so the test program can check every rule.
#pragma once

#include "core/common.hpp"

#include <vector>

namespace nv
{
enum Cabin : int
{
    CabinNone = 0,      // nobody's cabin is between us
    CabinShared = 1,    // we sit in the same vehicle
    CabinSeparated = 2, // one of us is inside a car the other isn't in
};

// A closed car's body and glass: what gets through within reach, and how dull. Enough to tell someone inside is talking,
// though hardly what they say: the treble that carries the words goes, the vowels and pitch stay (user, 2026-11-14, when
// a 500 Hz cut left nothing to hear over the street). It holds to kCabinFadeFromMeters and fades out by the reach, past
// which nothing gets through, since silence "with someone standing at your window could look like a broken link".
constexpr float kCabinWallGain = 0.45f; // about -7 dB
constexpr float kCabinWallCutoffHz = 1000.f;
constexpr float kCabinFadeFromMeters = 3.f;
constexpr float kCabinReachMeters = 5.f;

// A gap in a car's cabin: a window wound down or shot out, an open door, a roof that's off. In the world.
struct CarOpening
{
    Vec3 centre;
    Vec3 normal;          // one metre long, pointing out of the cabin
    float area = 0.f;     // square metres
    float openness = 0.f; // 0 shut .. 1 fully open; in between while a window winds or a door swings
};

// What a car's openings let through between a talker and a listener, against the voice with no car in the way.
struct CarSound
{
    float gain = 0.f;         // amplitude; 0 if nothing's open
    float cutoffHz = 16000.f; // the treble the way through the gaps keeps
    Vec3 arrival;             // where it seems to come from: the gaps nearest the listener, weighted by what each lets through
};

// The voice goes from the mouth out through a gap, and if the listener sits in a car of their own, in through one of
// theirs, turning at each gap like round a corner. A gap that faces away from where the voice goes next has the car's
// body in the way as well. A small gap lets through less than a side window's worth. Where only one car is open, the
// other's closed body muffles what comes through. Either car can be missing (nullptr). aNearMeters is SpatialInput's.
CarSound ThroughCars(const Vec3& aMouth, const Vec3& aEar, const std::vector<CarOpening>* aTalkerCar,
                     const std::vector<CarOpening>* aListenerCar, float aNearMeters);

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

    // With a cabin between us (separatedCabin), what its openings let through, from ThroughCars.
    float carOpenGain = 0.f;
    float carOpenCutoffHz = 16000.f;
    Vec3 carOpenArrival;
    bool carOpenAny = false;  // any gap in either car, by what the players report, so both work out ShouldSendNearby alike
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
    float carOpenShare = 0.f;      // 0 .. 1: of what crosses a cabin, how much came through its gaps; for echoes and the log
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
// no way round is ever shorter than the straight line, so this never stops a voice someone could hear. A closed cabin
// between us stops it past its reach, unless either car has a gap (aCarOpen), which both players know from what each
// reports about their own car.
bool ShouldSendNearby(float aDistance, float aSeparatedCabin, bool aCarOpen, float aFarMeters);

// Your radio mic: on while you hold the radio key, and while your game has you in combat (user, 2026-11-15). Never left on
// otherwise: a radio left on put every partner past its old 25 m cut at full clarity, so nobody ever heard anyone get far away
// (2026-11-14 logs). So partners play it at any distance, in a vehicle you share too, with no cut
// for being close. What you say for kTailMs after it goes off still goes on the radio: a word ends a little after the key comes
// up, and the mic's own processing holds the last of it back.
class RadioMic
{
public:
    static constexpr double kTailMs = 250.0;

    // Each returns true when it turns the radio mic on or off. Outside a session it stays off.
    bool SetSession(bool aInSession, double aNowMs);
    bool SetHeld(bool aHeld, double aNowMs);
    bool SetCombat(bool aInCombat, double aNowMs);

    bool On() const
    {
        return m_on;
    }
    bool InCombat() const
    {
        return m_inCombat;
    }
    // Whether what the mic sends now goes on the radio: while on, and for kTailMs after.
    bool OnAir(double aNowMs) const;

private:
    bool Settle(double aNowMs);

    bool m_inSession = false;
    bool m_held = false;
    bool m_inCombat = false;
    bool m_on = false;
    double m_tailUntilMs = -1e12;
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
