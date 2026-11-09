// What the plugin decides and the audio thread reads, and what the audio thread reports back for the log.
#pragma once

#include "wwise/places.hpp"

#include <atomic>
#include <cstdint>

namespace hs
{
// Where everything starts. tuning.ini can move these while playing.
inline constexpr float kStartThresholdDb = 85.f;
// How far the microphones come down. 0.57 left your own gun almost inaudible while there was no cup leak to carry it (user), and
// 0.35 was the stopgap. With the leak the microphones can go nearly silent during a bang, as a real headset's do.
inline constexpr float kStartDepthPerDb = 0.57f;
inline constexpr float kStartDeepestDb = 40.f;
inline constexpr float kStartLeakDb = -10.f;      // the cups' leak, as tuned by ear in NightCoop Voice
inline constexpr float kStartRecoilDb = 12.f;     // how much your own shot's lows are raised while worn; 0 is off. Was 6, then 9 (user asked for more)
inline constexpr float kStartThumpDb = 6.f;       // the same for other people's shots and for blasts, which felt muted without it (user)
inline constexpr float kStartLiftUnderDb = -38.f; // sounds under this get lifted, as talk-through does
inline constexpr float kStartHissDb = -64.f;
inline constexpr float kStartWidth = 0.75f;       // microphones on the cups tell less of where a sound is than ears do
// V's own voice. At +3 and -12 V stayed very easy to understand and didn't sell the effect, and at -22 the clean voice was still too
// present. With the air path fully out V sounded "very good. understandable too" (user), the body path alone carrying the words.
inline constexpr float kStartBodyDb = 5.f;        // V's lines through the skull: warmer
inline constexpr float kStartAirFloorDb = -60.f;  // what's always left of V's lines through the air: effectively nothing
inline constexpr float kStartAirOpenDb = -5.f;    // V's lines through the microphones when nothing's clamping them
inline constexpr float kStartGruntBodyDb = 8.f;   // V's grunts and breathing, as warm as felt "closer to self" (user)
inline constexpr float kStartGruntFloorDb = -60.f;
inline constexpr float kStartGruntOpenDb = -12.f; // -3 left them "too clear" in dynamic clamping (user)
// A gunshot drowns out your own voice whether or not you wear anything: this is how far V goes down, all of it, at the loudest bang.
inline constexpr float kStartMaskDb = -30.f;
// Except V's grunts and breathing in dynamic clamping, which stay: "all the chaos is suppressed but your can feel yourself breathe and
// it's a reminder of sorts" (user). They don't compete with the world as speech does. Noise cancelling drowns them out like V's lines.
inline constexpr float kStartGruntClampMaskDb = 0.f;
inline constexpr float kStartGruntBodyHz = 450.f; // below this, grunts reach V through the skull: lower is further inside your head
inline constexpr float kStartFootstepDb = 6.f;    // your own steps thud through your body
// Noise cancelling, from what such headphones generally do: the microphones cut the lows, the cups cut the highs, the middle
// gets the least of either.
inline constexpr float kStartNoiseLowDb = -26.f;
inline constexpr float kStartNoiseMidDb = -18.f;
inline constexpr float kStartNoiseHighDb = -28.f;
// During a bang: the cancelling can't keep up with something that sudden and there's no clamp, so only the cups are left, and those
// stop lows worst. So a gunshot hits harder in noise cancelling than in dynamic clamping.
inline constexpr float kStartNoiseBangLowDb = -8.f;
inline constexpr float kStartNoiseBangMidDb = -12.f;
inline constexpr float kStartNoiseBangHighDb = -22.f;

// There's no "not wearing it": the headset is always on your head, and Passthrough is it doing nothing.
enum class Mode : int
{
    Passthrough = 0,
    HearingProtection = 1, // level-dependent hearing protection: talk-through, and the clamp
    NoiseCancelling = 2,
};
inline constexpr int kModeCount = 3;

struct Control
{
    std::atomic<int> mode{static_cast<int>(Mode::Passthrough)}; // what the player chose
    std::atomic<bool> wornByTuning{false}; // temporary: always_worn=1 in tuning.ini
    std::atomic<bool> wheelFlipY{false};   // temporary: wheel_flip_y=1, if up and down on the wheel turn out reversed

    // The clamp on the world's bus, for nearby voices to follow.
    std::atomic<float> worldClamp{1.f};
    std::atomic<double> worldClampAtMs{-1e9};

    // Temporary, for tuning by ear in the game through tuning.ini.
    std::atomic<float> thresholdDb{kStartThresholdDb};
    std::atomic<float> depthPerDb{kStartDepthPerDb}; // of each dB over the threshold, how many come off
    std::atomic<float> deepestDb{kStartDeepestDb};
    std::atomic<bool> soundOn{true}; // everything but the clamp; off leaves only the clamp, to compare by ear
    std::atomic<float> leakDb{kStartLeakDb};
    std::atomic<float> recoilDb{kStartRecoilDb};
    std::atomic<float> thumpDb{kStartThumpDb};
    std::atomic<float> liftUnderDb{kStartLiftUnderDb};
    std::atomic<float> hissDb{kStartHissDb};
    std::atomic<float> width{kStartWidth};
    std::atomic<float> bodyDb{kStartBodyDb};
    std::atomic<float> airFloorDb{kStartAirFloorDb};
    std::atomic<float> airOpenDb{kStartAirOpenDb};
    std::atomic<float> gruntBodyDb{kStartGruntBodyDb};
    std::atomic<float> gruntFloorDb{kStartGruntFloorDb};
    std::atomic<float> gruntOpenDb{kStartGruntOpenDb};
    std::atomic<float> maskDb{kStartMaskDb};
    std::atomic<float> gruntClampMaskDb{kStartGruntClampMaskDb};
    std::atomic<float> gruntBodyHz{kStartGruntBodyHz};
    std::atomic<float> footstepDb{kStartFootstepDb};
    std::atomic<float> noiseLowDb{kStartNoiseLowDb};
    std::atomic<float> noiseMidDb{kStartNoiseMidDb};
    std::atomic<float> noiseHighDb{kStartNoiseHighDb};
    std::atomic<float> noiseBangLowDb{kStartNoiseBangLowDb};
    std::atomic<float> noiseBangMidDb{kStartNoiseBangMidDb};
    std::atomic<float> noiseBangHighDb{kStartNoiseBangHighDb};
    std::atomic<float> offsetDb[kDetectorCount];

    // For the log, taken every 10 s.
    std::atomic<float> loudestReading[kDetectorCount];
    std::atomic<uint32_t> detectorRuns[kDetectorCount];
    std::atomic<int> detectorsAlive{0};
    std::atomic<int> clampsAlive{0};
    std::atomic<float> lowestGain{1.f};
};
extern Control g_control;

// Everything back to where the mod starts.
void ResetControl();

// What the headset is doing right now: the player's choice, unless always_worn in tuning.ini turns Passthrough into hearing protection.
Mode EffectiveMode();
bool IsWorn(); // anything but Passthrough
bool DetectorsWanted();

// A tap: the next mode, Passthrough, Noise Cancelling, Hearing Protection and round again.
void CycleMode();
// The wheel's choice.
void ChooseMode(Mode aMode);
} // namespace hs
