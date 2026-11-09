#include "headset/control.hpp"

namespace hs
{
Control g_control;

void ResetControl()
{
    g_control.mode.store(static_cast<int>(Mode::Passthrough));
    g_control.wornByTuning.store(false);
    g_control.worldClamp.store(1.f);
    g_control.worldClampAtMs.store(-1e9);
    g_control.thresholdDb.store(kStartThresholdDb);
    g_control.depthPerDb.store(kStartDepthPerDb);
    g_control.deepestDb.store(kStartDeepestDb);
    g_control.soundOn.store(true);
    g_control.leakDb.store(kStartLeakDb);
    g_control.recoilDb.store(kStartRecoilDb);
    g_control.thumpDb.store(kStartThumpDb);
    g_control.liftUnderDb.store(kStartLiftUnderDb);
    g_control.hissDb.store(kStartHissDb);
    g_control.width.store(kStartWidth);
    g_control.bodyDb.store(kStartBodyDb);
    g_control.airFloorDb.store(kStartAirFloorDb);
    g_control.airOpenDb.store(kStartAirOpenDb);
    g_control.gruntBodyDb.store(kStartGruntBodyDb);
    g_control.gruntFloorDb.store(kStartGruntFloorDb);
    g_control.gruntOpenDb.store(kStartGruntOpenDb);
    g_control.maskDb.store(kStartMaskDb);
    g_control.gruntClampMaskDb.store(kStartGruntClampMaskDb);
    g_control.gruntBodyHz.store(kStartGruntBodyHz);
    g_control.footstepDb.store(kStartFootstepDb);
    g_control.noiseLowDb.store(kStartNoiseLowDb);
    g_control.noiseMidDb.store(kStartNoiseMidDb);
    g_control.noiseHighDb.store(kStartNoiseHighDb);
    g_control.noiseBangLowDb.store(kStartNoiseBangLowDb);
    g_control.noiseBangMidDb.store(kStartNoiseBangMidDb);
    g_control.noiseBangHighDb.store(kStartNoiseBangHighDb);
    for (int i = 0; i < kDetectorCount; ++i)
    {
        g_control.offsetDb[i].store(kDetectors[i].offsetDb);
        g_control.loudestReading[i].store(0.f);
        g_control.detectorRuns[i].store(0);
    }
    g_control.lowestGain.store(1.f);
}

Mode EffectiveMode()
{
    const auto chosen = static_cast<Mode>(g_control.mode.load(std::memory_order_relaxed));
    if (chosen == Mode::Passthrough && g_control.wornByTuning.load(std::memory_order_relaxed))
    {
        return Mode::HearingProtection;
    }
    return chosen;
}

bool IsWorn()
{
    return EffectiveMode() != Mode::Passthrough;
}

bool DetectorsWanted()
{
    return IsWorn();
}

void ChooseMode(Mode aMode)
{
    g_control.mode.store(static_cast<int>(aMode));
}

void CycleMode()
{
    ChooseMode(static_cast<Mode>((g_control.mode.load() + kModeCount - 1) % kModeCount)); // down the enum: 0, 2, 1
}
} // namespace hs
