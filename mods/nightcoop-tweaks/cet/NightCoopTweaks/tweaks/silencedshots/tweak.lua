-- Silenced shots: partners hear our silenced weapon.
--
-- NightCoop plays a partner's shot with the weapon's NPC sound, but a silenced
-- one with none ("weapon sound: a blank shot has no sound — silenced shot" in
-- its log). This plays the shot an NPC firing that weapon silenced makes, from
-- the game's audio metadata (tools/make-sound-tables.py), on partners' copy
-- of our body through NightCoop's SDK. The shooter's side: partners need
-- nothing. RECORD.md has why.
--
-- A shot is silenced by the game's own rule (ShootEvents.OnEnter): the weapon's
-- CanSilentKill stat above 0, which a silencer gives, and some iconics have
-- built in with no silencer attached (Panam's Overwatch).
--
-- An NPC's gun has single shots, bursts, or an automatic loop that its stop
-- event ends, and each weapon has some of these. A shot here is a single shot
-- where there is one; held fire on full auto, or a weapon with only a loop,
-- runs the loop for the firing sequence: from its first shot until the game
-- ends the sequence (WeaponTransition.EndShootingSequence, as the weapon goes
-- back to ready, reloads or is put away). A weapon with only bursts plays one
-- as the sequence starts and again while it goes on.

local Log = require("core/log")
local Ref = require("core/ref")
local Sounds = require("core/sounds")
local Shots = require("tweaks/silencedshots/sounds")

local Tweak = { name = "Silenced shots" }

local FALLBACK_SECONDS = 1.0 -- a loop ends after this long without a shot, should the sequence's end not come
local BURST_SECONDS = 0.6    -- a burst-only weapon held: another burst after this (a guess; the NPC's runs ~1.5 s)
local RESEND_SECONDS = 0.4   -- a loop's stop goes again, since a lost one would leave it firing at partners

local enabled = true
local pending = {} -- what the observers saw, for Update: { shot = { set, full, at } } or { ended = at }
local run          -- the sound going on at partners: { set, kind, voice, lastShot, lastBurst }
local resend       -- { event, at }: a loop's second stop, called off if that loop starts again first
local heard, played, unknown, runs = 0, 0, 0, 0
local report = "no silenced shot yet"

local function playerId()
    local player = Game.GetPlayer()
    return player and player:GetEntityID()
end

local function ours(scriptInterface)
    local player = Game.GetPlayer()
    local owner = scriptInterface.executionOwner
    return player ~= nil and owner ~= nil and Ref.Same(owner, player)
end

-- One voice per player, as the game gives each NPC one of the weapon's voices,
-- so two partners with the same gun differ.
local function voiceOf(entry)
    local peer = math.max(Sounds.LocalPeer(), 0)
    return entry.voices[(peer % #entry.voices) + 1]
end

local function kindFor(voice, shot)
    if shot.full and voice.loop then
        return "loop"
    elseif voice.single then
        return "single"
    elseif voice.loop then
        return "loop"
    elseif voice.burst then
        return "burst"
    end
    return nil
end

local function endRun()
    if run.kind == "loop" then
        local id = playerId()
        if id then
            if run.voice.loopStop then
                Sounds.Play(id, run.voice.loopStop, { important = true })
                resend = { event = run.voice.loop, at = os.clock() + RESEND_SECONDS }
            else
                Sounds.Play(id, run.voice.loop, { stop = true, important = true })
            end
        end
    end
    run = nil
end

local function play(shot)
    local entry = Shots[shot.set]
    if not entry then
        unknown = unknown + 1
        report = "no NPC shot sound known for the weapon's audio set '" .. shot.set .. "'"
        Log.Problem("Silenced shots: " .. report)
        return
    end
    local voice = voiceOf(entry)
    local kind = kindFor(voice, shot)
    local id = playerId()
    if not kind or not id then
        return
    end
    if run and (run.set ~= shot.set or run.kind ~= kind) then
        endRun()
    end

    if kind == "single" then
        Sounds.Play(id, voice.single)
        played = played + 1
    elseif kind == "loop" then
        if not run then
            -- a stop still due for an earlier run of this loop would end this one
            if resend and resend.event == voice.loop then
                resend = nil
            end
            Sounds.Play(id, voice.loop, { important = true })
            played = played + 1
            runs = runs + 1
            run = { set = shot.set, kind = kind, voice = voice }
        end
    elseif kind == "burst" then
        if not run or shot.at - run.lastBurst >= BURST_SECONDS then
            Sounds.Play(id, voice.burst)
            played = played + 1
            if not run then
                runs = runs + 1
            end
            run = run or { set = shot.set, kind = kind, voice = voice }
            run.lastBurst = shot.at
        end
    end
    if run then
        run.lastShot = shot.at
    end
    report = string.format("%d silenced shot(s), %d sound(s) sent, %d loop or burst run(s); last: %s, %s of %s%s",
        heard, played, runs, shot.set, kind, entry.settings, entry.fallback and " (no silenced NPC sound: the plain one)" or "")
end

-- ShootEvents.OnEnter runs once a shot, in the local player's weapon state
-- machine; partners' bodies have none.
local function onShot(scriptInterface)
    if not ours(scriptInterface) then
        return
    end
    local weapon = scriptInterface.owner
    if not weapon or not weapon:IsA("gameweaponObject") then
        return
    end
    local stats = Game.GetStatsSystem()
    if stats:GetStatValue(weapon:GetEntityID(), gamedataStatType.CanSilentKill) <= 0 then
        return
    end
    local mode = weapon:GetCurrentTriggerMode()
    heard = heard + 1
    table.insert(pending, { shot = {
        set = NameToString(weapon:GetWeaponRecord():AudioName()),
        full = mode ~= nil and EnumInt(mode:Type()) == EnumInt(gamedataTriggerMode.FullAuto),
        at = os.clock(),
    } })
end

function Tweak.Init()
    Observe("ShootEvents", "OnEnter", function(self, stateContext, scriptInterface)
        if not enabled then
            return
        end
        local ok, err = pcall(onShot, scriptInterface)
        if not ok then
            Log.Problem("Silenced shots: " .. tostring(err))
        end
    end)
    Observe("WeaponTransition", "EndShootingSequence", function(self, weapon, stateContext, scriptInterface)
        local ok, err = pcall(function()
            if ours(scriptInterface) then
                table.insert(pending, { ended = os.clock() })
            end
        end)
        if not ok then
            Log.Problem("Silenced shots: " .. tostring(err))
        end
    end)
end

function Tweak.Update()
    local now = os.clock()
    local seen = pending
    pending = {}
    for _, item in ipairs(seen) do
        if item.shot then
            play(item.shot)
        elseif run then
            endRun()
        end
    end
    if run and now - run.lastShot >= FALLBACK_SECONDS then
        endRun()
    end
    if resend and now >= resend.at then
        local id = playerId()
        if id then
            -- the second try stops the loop's own event, in case the stop event didn't reach it
            Sounds.Play(id, resend.event, { stop = true, important = true })
        end
        resend = nil
    end
end

function Tweak.Shutdown()
    if run then
        endRun()
    end
end

function Tweak.DrawOverlay()
    local was = enabled
    enabled = ImGui.Checkbox("Partners hear your silenced shots", enabled)
    if was and not enabled and run then
        endRun()
    end
    ImGui.TextWrapped(report)
    if unknown > 0 then
        ImGui.TextWrapped(string.format("%d shot(s) of a weapon with no known sound", unknown))
    end
end

return Tweak
