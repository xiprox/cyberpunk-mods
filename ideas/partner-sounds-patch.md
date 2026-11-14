# Partner sounds patch

Stopping partners' player-only sounds (ground slams, burning, detection, falls) from playing as if they were yours in NightCoop.
The user wants it as a local patch while the real fix waits on NightCoop's developer.
Scouted on 2026-11-09; nothing built and nothing tested in the game.
NightCoop Tweaks' Horn and Silenced shots tweaks (2026-11-13, its RECORD.md) already fix two other partner sounds, through the SDK's `PlaySoundOn`.

## What was found

Partner bodies are real `PlayerPuppet`s, and half the game's audio events (13,510 of 26,440 in `base\sound\event\eventsmetadata.json`, those with `maxAttenuation` 0) have no distance falloff.

- **Ground slams:** confirmed by NightCoop's `fx_self_witness` log line. It replays `ground_slam_main.effect` and `ground_slam_earthquake_lv1.effect` natively.
  The same files serve your own slam, so an archive edit can't tell them apart.
- **Burning:** `BurningSFX` is a `PlaySFXEffector` guarded only by `IsPlayerPrereq`; how it reaches a partner isn't in the logs yet.
  `PlaySFXEffector` isn't in NightCoop's do-not-replace tables, so a redscript wrap comparing the owner with the local player works.
  `nme_fx_burning_start` (30 m falloff) is the sound a partner should make instead of `vfx_fullscreen_burning_start`.
- **Falls and other jumps:** `lcm_player_double_jump` and `lcm_falling_wind_loop` have no falloff, but a partner's body has no state machine, so how they arrive is unknown; animation events are the guess.
- **Detection (2.5 addresses):** `ui_gmpl_stealth_*` is played with no emitter by exe+0x640228, from the `UI_Stealth` blackboard, written by exe+0x6408d8 from a table at this+0x240. Whether partner bodies get into that table is unproven.

## The plan

- A RED4ext detour on `AK::SoundEngine::PostEvent`, which the exe exports by name along with `Query::GetPosition` and `SetGameObjectOutputBusVolume` ([NightCoop Voice's RECORD.md](../mods/nightcoop-voice/RECORD.md), 2026-11-08, has how the game's Wwise is reached).
  First a census: log each event, its emitter and its distance through one co-op session.
- Order: the burning script patch and the census, then the filter, detection last.
- Don't wrap `gameObject.PlaySound*` with a skip: NightCoop relies on it.
