# What not to hook: functions co-op relies on

NightCoop changes game functions while the game runs: it puts a guard in front of hundreds of script functions, sends single
calls inside the game's script bodies to itself, and detours about 140 native functions. A mod that replaces one of them can
switch a part of co-op off without any error: a partner's body starts acting as your V, a quest scene stops waiting for
everybody, a car mirror drives itself.

NightCoop looks for such overlaps itself wherever it can (see [What NightCoop finds itself](#what-nightcoop-finds-itself)).
**What it cannot find is only on this page** — read [What NightCoop cannot find](#what-nightcoop-cannot-find) before you
replace anything in the [tables](#the-tables).

## In short

Fine on every function in the tables:

- redscript `@wrapMethod` that calls `wrappedMethod(...)` on every path;
- CET `Observe` / `ObserveBefore` / `ObserveAfter`;
- CET `Override` that calls the original (its last argument) every time;
- a native detour that calls the original every time;
- Codeware callbacks, event listeners, reading state.

Not fine on a function in the tables (co-op breaks there, see the area's line in the table):

- redscript `@replaceMethod`, `@replaceGlobal`;
- `@wrapMethod` that never calls `wrappedMethod`, or calls it only sometimes;
- `@addMethod` on a subclass that overrides a function NightCoop wraps in the base class, without calling `super`;
- CET `Override` that does not call the original;
- a native detour that returns without calling the original, a byte patch inside the function, a replaced vtable slot.

If your mod has to replace one of them:

1. Ask NightCoop: `hookCoopUses` (C), `NightCoopSdk.HookCoopUses(cls, fn)` (redscript, CET). A non-zero answer — co-op relies
   on it now: keep the original running while NightCoop is in a session (`where()` / `InSession()`).
2. Declare it: `hookDeclare` / `NightCoopSdk.HookDeclare(id, cls, fn, flags)` (passport flag `NCSDK_MOD_USES_HOOKS`). The player
   then gets the same warning as for the overlaps NightCoop finds itself, and your mod's name is in it.
3. Remember that in a session the class `PlayerPuppet` is also the **partners' bodies**: a `@wrapMethod(PlayerPuppet)` runs for
   them too. Check `NightCoopSdk.EntityIsMine(entity)` (C: `entityIsMine`) before you treat a `PlayerPuppet` as the local V.

## How NightCoop hooks — and why the order matters

**Script functions.** NightCoop puts its guard in front of the function's body after redscript has compiled everything: in
front of your `@replaceMethod` body and of all `@wrapMethod` wrappers. So a guard survives a replacement; what does not
survive:

- a **redirect** (NightCoop sends one call inside the game's body to itself, e.g. the police chase car of a guest is asked
  of the host): it needs the game's call in the body. Under `@replaceMethod` the redirect goes into your body only if you
  kept that call; otherwise it is not placed (NightCoop names your mod in its log when it found your `.reds`). Under
  `@wrapMethod` NightCoop follows the chain of wrappers to the copy that holds the game's body and puts the redirect there.
  If one of the wrappers never calls `wrappedMethod`, the game's body is unreachable: the redirect is not placed;
- what the game's body did that co-op relies on when the guard lets the call through.

**CET.** `Observe` and `Override` swap the function for a native one of CET's; the original body (with NightCoop's guard, if
NightCoop came first) moves to CET's copy. Then:

- CET came after NightCoop: `Observe` calls the copy — NightCoop's guard runs. `Override` runs NightCoop's guard only when the
  Lua function calls its last argument;
- CET came first: the function is native now, NightCoop's script hooks cannot be put on it at all. CET mods usually hook in
  `onInit`, when the player first appears; most of NightCoop's script hooks are placed earlier, at the first game frame — but
  those placed later (on a switch, at session start, with retries) can come after.

**Natives.** NightCoop detours through RED4ext. A hook another module puts on the same entry later sits above NightCoop's and
runs first; one put earlier sits below. Each hook runs the next one only if it calls the original.

## What NightCoop finds itself

All of it goes to NightCoop's log (`hooks: …`), one line per overlap; overlaps that can break co-op also give one note on the
screen with the mods' names; the full list — `red4ext/plugins/NightCoop/logs/nightcoop-hooks.txt`. Switch: `hook_overlap`.

| What | How NightCoop finds it |
|---|---|
| redscript `@replaceMethod`, `@wrapMethod` (with or without `wrappedMethod`), `@addMethod` on a subclass, `@replaceGlobal` on a function in the tables | reads `.reds` under `r6/scripts` and `red4ext/plugins` |
| redscript `@wrapMethod` wrappers on a function NightCoop hooks, and whether each calls `wrappedMethod` | at run time, from the bytecode chain (even without the `.reds` files) |
| CET `Override`, `Observe`, `ObserveBefore`, `ObserveAfter` with literal class and function names | reads `.lua` under `bin/x64/plugins/cyber_engine_tweaks/mods` |
| A script function NightCoop hooked became native afterwards (CET or a mod doing the same) | at run time |
| A script function NightCoop wanted to hook was already native (CET first): the hook is not placed | at run time (the mod's name — from the `.lua` scan when the names are literal) |
| NightCoop's guard is no longer in the body (a script reload, another mod rewriting bytecode at run time) | at run time |
| Another module's hook on the entry of a native function NightCoop detours, before or after NightCoop | the entry's jump chain ends in that module |
| Keys: a CET hotkey (`bindings.json`) or an Input Loader file (`r6/input/*.xml`) on a key NightCoop reads | reads both files |
| Popular mods with a known overlap ([table](#popular-mods-with-a-known-overlap)) | by folder or file name |
| What your mod declares through `hookDeclare` | as above, with your mod's name |

## What NightCoop cannot find

These overlaps break co-op the same way, but NightCoop has no way to see them. They are only on this page.

1. **`@replaceMethod` leaves no trace in the running game** — the body is simply another. NightCoop knows of it only from the
   `.reds` text, so it misses:
   - `.reds` files that another RED4ext plugin adds to the compilation from any other folder;
   - REDmod script mods (`mods/<mod>/scripts/**/*.script`): the game's own compiler replaces whole script files;
   - a precompiled `final.redscripts` shipped by a mod;
   - and it cannot evaluate `@if(...)`: an annotation inside a conditional block is reported as if it were compiled.
2. **CET hooks whose names are built at run time** (variables, tables, string concatenation, a helper library that calls
   `Override` for you): NightCoop sees that a function it hooks became native, but cannot say which mod did it.
3. **Whether a hook calls the original.** NightCoop never knows whether a CET `Override` calls its last argument, whether a
   native detour calls the original, or whether a `@wrapMethod` calls `wrappedMethod` on every path (it sees only that the call
   is in the body somewhere).
4. **Native hooks off the entry**: a byte patch inside a function (PhotoMode-EX patches `PhotoModeSystem_ProcessAttribute`),
   a replaced vtable slot, an import table patch. NightCoop checks only the entries of the functions it detours itself.
5. **Functions NightCoop calls but does not hook.** NightCoop reads and drives the game through many functions it does not
   hook (the radio through `PocketRadio` and `VehicleObject.GetCurrentRadioIndex`, teleports, spawns, facts, the time system).
   A mod that replaces one changes what NightCoop gets back; NightCoop compares only with the functions it hooks.
6. **The way to a hooked function.** A replaced *caller* that no longer calls a function NightCoop hooks means NightCoop's hook
   never runs. NightCoop does not follow call graphs.
7. **Hooks put later.** A mod that hooks on a hotkey or from a menu later is noticed at the next world load at the latest.
8. **Script reloads.** After a redscript hot reload or CET "reload all mods", NightCoop notices that its hooks are gone,
   but does not put them back: restart the game.
9. **Data, not functions.** TweakDB records, ArchiveXL resources and saved settings are not hooks; NightCoop's mods check
   compares only the files both players have. See [Data co-op relies on](#data-co-op-relies-on).
10. **Keys outside the two files**: the game's Controls menu (user settings), keys a RED4ext plugin reads itself.

## Data co-op relies on

Changing these records (TweakXL, CET `TweakDB:SetFlat`, ArchiveXL) is not seen by NightCoop's checks:

| Record / field | What co-op does with it |
|---|---|
| `photo_mode.general.recordIDForPhotoModePuppet` | The template of partners' photo mode copies |
| `.priority` of character records (`Quest`) | A story NPC is one body for everybody and is led by the host |
| `OutfitSlots.*` (Equipment-EX) and `placementSlots[0]` of clothing records | Partners' outfits are sent by these slots |
| `Vehicle.vehicle_list.list` | The garage: which cars a guest owns in the host's world |
| Records of items, vehicles, NPCs a partner does not have | A partner's car or NPC of a mod the other player lacks is not built there |

## What NightCoop changes on purpose

Your mod may notice these; they are deliberate, so the shared world stays one:

- `TimeDilationHelper.SetTimeDilationWithProfile` (slow motion of the world) is off in co-op: one player's slow motion would
  slow everybody. Only the player's own Sandevistan tempo is shown to partners;
- photo mode does not freeze the world, pause its audio or stop quest timers (`photo_live`);
- the pause menu does not pause the world unless every player is in a menu; a guest's time skip goes through the host;
- loads of a save inside a session go through the session rules;
- a guest gets the host's weather, quest facts, journal and police;
- partners' bodies are `PlayerPuppet`s, and many `PlayerPuppet` functions answer differently for them (see the player table).

## Declaring your hooks (SDK)

C (NightCoop with `hookDeclare`; check `NCSDK_HAS(api, hookDeclare)`):

```c
/* passport: info.flags |= NCSDK_MOD_USES_HOOKS; */
api->hookDeclare(mod, "PlayerPuppet", "OnStatusEffectApplied", 0, NCSDK_HOOK_REPLACES);
api->hookDeclare(mod, NULL, NULL, (uint64_t)myDetouredEntry, NCSDK_HOOK_WRAPS);   /* a native entry you detour */
if (api->hookCoopUses("PlayerPuppet", "OnStatusEffectApplied", 0) > 0) { /* keep the original while in a session */ }
```

redscript (guard it with `@if(ModuleExists("NightCoop"))`, so the mod compiles without NightCoop):

```swift
@if(ModuleExists("NightCoop"))
private func DeclareToNightCoop() -> Void {
  NightCoopSdk.HookDeclare("author.mymod", "PlayerPuppet", "OnStatusEffectApplied", EnumInt(NightCoopSdkHookFlag.Replaces));
}
```

CET (`sdk/cet/nightcoop_sdk.lua`):

```lua
Sdk.hookDeclare("author.mymod", "PlayerPuppet", "OnStatusEffectApplied", Sdk.HOOK.REPLACES)
if Sdk.hookCoopUses("PlayerPuppet", "OnStatusEffectApplied") ~= 0 then --[[ call the original ]] end
for _, k in ipairs(Sdk.coopKeys()) do print(k.name, k.action) end
```

## Log lines

| Line | Means |
|---|---|
| `hooks: <mod> (<file>:<line>) — @replaceMethod <Class>.<fn>; NightCoop wraps it (<ids>; <area>): …` | A mod's declaration on a function NightCoop hooks, and what follows |
| `hooks: <Class>.<fn> — NightCoop could not wrap it: <who> took it over before NightCoop …` | CET (or a mod doing the same) was first: that co-op part is off |
| `hooks: <Class>.<fn> (<id>) has N redscript @wrapMethod wrapper(s) of other mods: …` | Other mods wrap it; whether the game's body still runs |
| `hooks: <module> hooked <function> … after NightCoop / before NightCoop` | Another module's native hook on the same entry |
| `hooks: key <key> — <CET mod / Input Loader file> uses it, NightCoop reads it too …` | One press does both |
| `script patch '<id>': no call of <fn> in the body (… @wrapMethod wrapper(s) …)` | A redirect not placed, and why |

## The tables

The areas: what NightCoop does there and what breaks when the game's function is replaced. A class not listed may still
matter through the functions NightCoop calls (point 5 above).

<!-- hook-tables:begin -->
### Script functions NightCoop wraps or redirects

A function marked `*` is hooked only in some conditions (a switch, or the other game version). "Redirect" — NightCoop sends one call inside the game's body to itself: that body must stay the game's.


#### player body and state

_partners' bodies are PlayerPuppets in your game and NightCoop keeps their events, looks, poses and animation apart from your own V; replaced, a partner's body acts as your V (death, items, police) or looks wrong._

| Class | Functions | Redirect |
|---|---|---|
| `BountyManager` | `CompleteBounty` |  |
| `DeathDecisions` | `EnterCondition` |  |
| `DeathDecisionsWithResurrection` | `ToResurrect` |  |
| `EquipmentSystemPlayerData` | `EquipItem*` |  |
| `HighLevelTransition` | `EvaluateSettingCustomDeathAnimation`, `SetIsResurrectionAllowedBasedOnState`, `SetPlayerDeathAnimFeatureData*` |  |
| `PlayerPuppet` | `OnBeingNoticed`, `OnBeingTargetByLaserSight`, `OnCarHitPlayer`, `OnClearBeingNoticedBB`, `OnClearItemAppearanceEvent`, `OnDeath`, `OnDetach`, `OnEvaluateEncumbranceEvent`, `OnGameAttached`, `OnInteraction`, `OnInventoryEmpty`, `OnItemAddedToInventory`, `OnItemAddedToSlot`, `OnItemBeingRemovedFromInventory`, `OnItemChangedEvent`, `OnItemRemovedFromSlot`, `OnRequestComponents`, `OnResetItemAppearanceEvent`, `OnRewardEvent`, `OnStatusEffectApplied`, `OnStatusEffectRemoved`, `OnTargetNeutraliziedEvent`, `OnUnderwearEquipFailsafeEvent`, `ShouldRegisterToHUD` |  |
| `ResurrectDecisions` | `ToDeath` |  |
| `RPGManager` | `AwardExperienceFromDamage`, `ForceItemTier*`, `GetBuildScore`, `GiveReward*` |  |
| `VendorDataManager` | `Initialize` |  |

#### NPCs, AI, combat and police

_every NPC is led by one player and copied to the others, senses, threats, hits and police go by the right player; replaced, NPC copies act on their own and fights differ between players._

| Class | Functions | Redirect |
|---|---|---|
| `AIActionHelper` | `ShouldShootDirectlyAtTarget`, `TryChangingAttitudeToHostile` |  |
| `AIActionTarget` | `GetObjectLegacy`, `GetVehicleObject` | yes |
| `AICondition` | `Check` | yes |
| `AIMoveCommandsDelegate` | `DoStartFollowTarget`, `DoStartMoveOnSpline` |  |
| `AIWeapon` | `Fire` |  |
| `BaseScriptableAction` | `CompleteAction`, `IsPossible`, `StartAction` |  |
| `CallPolice` | `Activate` |  |
| `CheckGameDifficulty` | `Check` | yes |
| `CombatGadgetHelper` | `SpawnPhysicalImpulse*` |  |
| `DamageManager` | `CalculateTargetModifiers` |  |
| `DamageSystem` | `PreProcessVehicleTarget` | yes |
| `FinisherAttackEvents` | `PlayFinisherGameEffect` |  |
| `gameDamageSystem` | `CalculateGlobalModifiers`, `CalculateSourceModifiers`, `CalculateSourceVsTargetModifiers`, `DealDamages`, `PreProcessVehicleTarget`, `ProcessArmor`, `ProcessBikeMelee`, `ProcessBlockAndDeflect`, `ProcessDamageReduction`, `ProcessEffectiveRange`, `ProcessEvasion`, `ProcessLocalizedDamage`, `ProcessMitigation`, `ProcessOnVehicleMitigation`, `ProcessPlayerIncomingDamageMultiplier`, `ProcessStealthAttack`, `SendDamageRequestToPreventionSystem` |  |
| `gameEffector` | `GetApplicationTarget(EntityID)`, `GetApplicationTarget*` |  |
| `gameObject` | `ChangeAttitudeToHostile`, `CheckIfPreventionShouldReact`, `IsPlayer*`, `IsTaggedinFocusMode*`, `OnVehicleHit`, `PlaySound*`, `TagObject*`, `UntagObject*` |  |
| `gamePreventionSpawnSystem` | `SpawnRequestFinished` |  |
| `gameTargetShootComponent` | `HandleMissed`, `ShouldBeHit` |  |
| `IsNPCInActivePoliceChase` | `Check` |  |
| `IsNpcPlayingMountingAnimationPrereq` | `IsFulfilled*` |  |
| `NPCPuppet` | `IsInCombatWithTarget`, `OnHitAnimation`, `OnIncapacitated`, `OnSecuritySystemAgentTrackingPlayer`, `OnStatusEffectApplied`, `OnVehicleRammedEvent`, `SwitchTargetPlayerTrackedAccuracy`, `TriggerRagdollBehavior`, `TriggerRagdollBehaviorEnd` | yes |
| `PoliceAgentRegistry` | `IsPoliceInCombatWithPalyer` |  |
| `PreventionSystem` | `ChangeHeatStage`, `CombatStartedRequestToPreventionSystem`, `CreateNewPreventionDamageRequest*`, `GetHeatStage`, `GetLastKnownPlayerPosition`, `GetPlayer`, `IsChasingPlayer`, `IsPoliceUnawareOfThePlayerExactLocation`, `RequestAVSpawnAtPosition`, `RequestUnitSpawn`, `ShouldReactionBeAggressive`, `SpawnFallbackUnits`, `SpawnPipeline`, `SpawnPoliceVehicle`, `SpawnRoadblockade`, `TrySpawnPoliceOnFootFallback` |  |
| `ReactionManagerComponent` | `DidTargetMakeMeAlerted`, `HandleCrowdReaction`, `IsPlayerAiming`, `IsPlayerFearThreat`, `OnCrowdReaction`, `OnDetectedEvent`, `OnStanceLevelChanged`, `SafeToExitFear`, `SafeToExitPanicFear`, `ShouldFearInPlace`, `ShouldFearWhileAggressiveCrowdNPCCombat`, `TriggerFacialLookAtReaction`, `TriggerPendingReaction`, `TriggerReactionBehaviorForCrowd` | yes |
| `ScriptedPuppet` | `CanRagdoll`, `DropHeldItems`, `DropItemFromSlot`, `DropWeaponFromSlot`, `GetRecord*`, `IsQuickHackAble`, `OnDamageReceived`, `OnKillRewardEvent`, `SendQuickhackCommands*`, `SetSenseObjectType*`, `UpdateLootInteraction` |  |
| `ScriptedPuppetPS` | `SetWasIncapacitated` |  |
| `SecuritySupportListener` | `Construct` | yes |
| `senseComponent` | `IsPlayerRecentlyDroppedThreat`, `PlayerEnteredPerception`, `ReevaluateDetectionOverwrite`, `RefreshCombatDetectionMultiplier*`, `SendDetectionRiseEvent`, `ShouldStartDetectingPlayer` | yes |
| `SetTopThreatToCombatTarget` | `Activate` |  |
| `ShouldNPCRetreatFromMaxTacEncounter` | `Check` | yes |
| `SimpleCombatConditon` | `Check` | yes |
| `SpatialQueriesHelper` | `IsTargetReachable` |  |
| `StimBroadcasterComponent` | `SendDrirectStimuliToTarget` |  |
| `TakedownGameEffectHelper` | `FillTakedownData` |  |
| `UncontrolledMovementEffector` | `ActionOn` |  |
| `UploadFromNPCToPlayerListener` | `OnStatPoolAdded` |  |

#### population and crowd

_the host leads the crowd for everybody; replaced, NPCs pop in or vanish where partners look._

| Class | Functions | Redirect |
|---|---|---|
| `JoinTrafficOnFoot` | `Update` | yes |

#### vehicles

_partners' cars are mirrors led by their owners; replaced, mirrors drive themselves, seats and hits go wrong._

| Class | Functions | Redirect |
|---|---|---|
| `AvHoverIdleSFXBehaviour` | `Activate` |  |
| `AvStartAscentSFXBehaviour` | `Activate` |  |
| `AvStartDescentSFXBehaviour` | `Activate` |  |
| `DelamainTaxiComponent` | `OnFactChanged`, `OnGameAttach`, `OnGameDetach`, `OnVehicleFinishedMountingEvent`, `OnVehicleParkedEvent`, `OnVehicleStartedMountingEvent` |  |
| `gameuiVehicleShopGameController` | `CheckFact` |  |
| `PsychoSquadAvHelperClass` | `OnMaxTacFearEventDelayed`, `OnTurnOnPsychoSquadAvCammoEventDelayed` |  |
| `TurnOffPsychoSquadAvCammo` | `Activate` |  |
| `TurnOffPsychoSquadAvCammoImmediatly` | `Activate` |  |
| `TurnOnPsychoSquadAvCammoImmediatly` | `Activate` |  |
| `VehicleComponent` | `DamagePassengerInCollision`, `IsSlotOccupied`, `OnExplodeEvent` |  |
| `VehicleComponentPS` | `OnVehicleOverrideAccelerate`, `OnVehicleOverrideExplode`, `OnVehicleOverrideForceBrakes` |  |

#### quests, facts, scenes and dialogs

_the host's world decides quests, facts, scenes and choices, and scenes wait for everybody; replaced, the story splits between players._

| Class | Functions | Redirect |
|---|---|---|
| `DialogChoiceLogicController` | `SetChoiceText` |  |
| `DialogHubLogicController` | `SetupTitle`, `UpdateDialogHubData` |  |
| `dialogWidgetGameController` | `OnDialogsActivateHub`, `OnDialogsSelectIndex` |  |
| `FastForwardActiveEvents` | `OnEnter` |  |
| `FastTravelSystem` | `IsFastTravelEnabled*`, `OnRestored`, `PerformFastTravel` |  |
| `MessengerDialogViewController` | `ActivateReply` |  |
| `PhoneMessageNotificationsGameController` | `OnAction` |  |
| `PhoneSystem` | `OnPickupPhone*`, `OnUsePhone` |  |
| `ScenesFastForwardTransition` | `StartGlitchFx`, `StopGlitchFx` |  |
| `SubtitleLineLogicController` | `SetLineData` |  |

#### time and pause

_time, pause and slow motion are the same for everybody; replaced, one player's pause or photo mode stops the others, or clocks drift apart._

| Class | Functions | Redirect |
|---|---|---|
| `CreditsGameController` | `OnUninitialize` |  |
| `GameTimeUtils` | `CanPlayerTimeSkip`, `FastForwardPlayerState` |  |
| `gameuiPhotoModeMenuController` | `OnAddAdditionalMenuItem`, `OnAddMenuItem` |  |
| `gameuiTimeskipGameController` | `Apply` |  |
| `MenuScenario_FinalBoards` | `OnEnterScenario` |  |
| `MenuScenario_FinalBoardsEp1` | `OnEnterScenario` |  |
| `PauseMenuBackgroundGameController` | `OnInitialize`, `OnUninitialize` | yes |
| `TimeDilationFocusModeDecisions` | `EnterCondition` |  |
| `TimeDilationHelper` | `SetTimeDilationWithProfile` |  |
| `TimeDilationPhotomodeDecisions` | `EnterCondition` |  |
| `TutorialPopupGameController` | `PauseGame` |  |

#### saves and loading

_loads and saves in a session go through the session rules; replaced, a load leaves the session broken._

| Class | Functions | Redirect |
|---|---|---|
| `DeathMenuGameController` | `HandleMenuItemActivate` |  |
| `LoadGameMenuGameController` | `LoadGame`, `OnInitialize`, `OnLoadSaveInGameCanceled`, `OnSaveMetadataReady`, `OnSavesForLoadReady`, `OnUninitialize` |  |

#### menus and HUD

_NightCoop's menu items, notes, map pins and vote windows live here; replaced, they are gone._

| Class | Functions | Redirect |
|---|---|---|
| `CharacterCreationBackstorySelectionMenu` | `OnIntroComplete`, `OnReleaseCorpo`, `OnReleaseNomad`, `OnReleaseStreet` |  |
| `characterCreationLifePathBtn` | `OnHoverOut`, `OnHoverOver` |  |
| `characterCreationSummaryMenu` | `NextMenu`, `OnOutroComplete` |  |
| `DifficultySelectionMenu` | `NextMenu*`, `OnHoverOverDifficulty0`, `OnHoverOverDifficulty1`, `OnHoverOverDifficulty2`, `OnHoverOverDifficulty3`, `OnPressDifficulty0`, `OnPressDifficulty1`, `OnPressDifficulty2`, `OnPressDifficulty3` |  |
| `EngagementScreenGameController` | `OnInitialize` |  |
| `ExpansionNewGame` | `NextMenu*`, `OnHoverOverBaseGame`, `OnHoverOverExpansion`, `OnIntroComplete`, `OnPressBaseGame`, `OnPressExpansion` |  |
| `gameuiBaseCharacterCreationController` | `OnInitialize`, `OnRelease`, `OnUninitialize` |  |
| `gameuiBaseWorldMapMappinController` | `ComputeRootState`, `PlayHideShowAnim` |  |
| `gameuiInGameMenuGameController` | `OnInitialize`, `OnSavingComplete` |  |
| `gameuiMappinUIUtils` | `MappinToDescriptionString`, `MappinToString`, `MappinToTexturePart` |  |
| `gameuiMenuItemListGameController` | `AddMenuItem*`, `Clear*`, `OnMenuItemActivated`, `ShouldAllowExitGameMenuItem` |  |
| `gameuiMinimapContainerController` | `CreateMappinUIProfile` |  |
| `gameuiPreGameMenuGameController` | `OnInitialize` |  |
| `gameuiWorldMapMenuGameController` | `OnInitialize`, `OnUninitialize` |  |
| `gameuiWorldMappinsContainerController` | `CreateMappinUIProfile` |  |
| `GenericNotificationController` | `OnAction` |  |
| `HUDManager` | `JumpToNextTarget` |  |
| `HUDProgressBarController` | `OnInitialize` |  |
| `LootingGameController` | `OnUpdateData` |  |
| `MenuScenario_PauseMenu` | `OnBack` |  |
| `MinimapPOIMappinController` | `ComputeRootState` |  |
| `MinimapStealthMappinController` | `FadeOut` |  |
| `OnscreenMessageGameController` | `OnInitialize`, `OnScreenMessageUpdate` |  |
| `PauseMenuGameController` | `OnGlobalRelease`, `OnInitialize`, `OnListRelease`, `OnMenuItemActivated`, `OnUninitialize` |  |
| `QuickHackMappinController` | `UpdateView` |  |
| `QuickhacksListGameController` | `ApplyQuickHack*`, `OnQuickhackStarted`, `SelectData*` |  |
| `ShardNotificationController` | `OnUninitialize`, `PauseGameState` | yes |
| `SingleplayerMenuGameController` | `HandleMenuItemActivate`, `OnContinueButtonEnter`, `OnGlobalRelease`, `OnInitialize`, `OnListRelease`, `OnSaveMetadataReady`, `OnSavesForLoadReady`, `OnUninitialize` |  |
| `WarningMessageGameController` | `OnInitialize` |  |

#### world, physics and effects

_explosions, effects, loot and weather are shared; replaced, players see different worlds._

| Class | Functions | Redirect |
|---|---|---|
| `BaseGrenade` | `Detonate` |  |
| `DropAction` | `CompleteAction` |  |
| `FocusModeTaggingSystem` | `OnActionWithOwner*`, `TagObject`, `UntagObject` |  |
| `gameItemDropObject` | `OnGameAttached` |  |
| `LoadListItem` | `IsCloud*` |  |

#### devices, doors and lifts

_doors, lifts and devices are one for everybody; replaced, they differ between players._

| Class | Functions | Redirect |
|---|---|---|
| `ComputerInkGameController` | `ResolveQuestInfo` |  |
| `DataTerm` | `TeleportToExitNode` |  |
| `Device` | `OnDeath` |  |
| `DisarmComponent` | `ArmOwner`, `DisarmOwner` |  |
| `DisposalDevice` | `OnDisposeBody`, `TakedownAndDispose` |  |
| `Door` | `MoveDoor`, `OnDoorTriggerDelayedEvent` |  |
| `DoorControllerPS` | `GetQuestActionByName` |  |
| `DropPointControllerPS` | `OnDepositQuestItems` |  |
| `ExplosiveDevice` | `DoAdditionalGameEffect`, `DoAttack`, `StartExplosionPipeline` |  |
| `GenericDevice` | `OnCustomAction` |  |
| `LiftDevice` | `OnAreaEnter`, `OnAreaExit`, `OnArrivedAt`, `OnInitializeFloorsData`, `OnLiftStartDelayEvent`, `OnQuestForceGoToFloor`, `OnQuestGoToFloor`, `OnQuestSetLiftSpeed`, `SendLiftStartDelayedEvent` | yes |
| `ScriptableDeviceAction` | `CompleteAction` |  |
| `SecurityTurret` | `OnDeath`, `SetAsIntrestingTarget` |  |

#### other

_co-op relies on it._

| Class | Functions | Redirect |
|---|---|---|
| `PlayerGameplayRestrictions` | `RequestFists*` |  |
| `ShouldRetreatBehaviorStop` | `Check` | yes |

### Native functions NightCoop detours

By the RED4ext address library hash (the same on 2.31 and 2.5). "May skip" — NightCoop's detour can answer without calling the original: a hook of another mod below it does not run then.

| Area | Hash | Game function | NightCoop part | May skip |
|---|---|---|---|---|
| player body and state | `1582048687` | BodyController Apply | partner bodies wear the partner's look |  |
| player body and state | `489494088` | EntityBuilder ExtractComponentsJob | partner bodies get the player rig and graph |  |
| player body and state | `2327646404` | PlayerUseWorkspot action end | no foreign first-person camera in a seat action |  |
| player body and state | `2635993388` | PlayerUseWorkspot action start | no foreign first-person camera in a seat action |  |
| player body and state | `1488071616` | TPP representation look query | partner bodies wear the partner's look |  |
| player body and state | `3089905793` | TPP view appearance change | partner bodies wear the partner's look |  |
| player body and state | `3247117892` | animation controller: external event | the animation stream of our V to partners | yes |
| player body and state | `3598063243` | animation controller: set bool input | the animation stream of our V to partners | yes |
| player body and state | `316482401` | animation controller: set feature | the animation stream of our V to partners | yes |
| player body and state | `3216184875` | animation controller: set float input | the animation stream of our V to partners | yes |
| player body and state | `3215201830` | animation controller: set int input | the animation stream of our V to partners | yes |
| player body and state | `953293729` | animation controller: set quaternion input | the animation stream of our V to partners | yes |
| player body and state | `3828226594` | animation controller: set vector input | the animation stream of our V to partners | yes |
| player body and state | `2074943978` | animation graph output write-back | pose of partner bodies and NPC copies |  |
| player body and state | `1245585201` | animation wrapper weight write | weapon animation sets of our V to partners |  |
| player body and state | `2783782033` | attach animation subgraph to slot | fire and melee subgraphs of our V to partners |  |
| player body and state | `4287044418` | body part job | partner bodies wear the partner's look |  |
| player body and state | `2592283144` | body part job | partner bodies wear the partner's look |  |
| player body and state | `3043040726` | body part job | partner bodies wear the partner's look |  |
| player body and state | `4190576795` | body parts controller acquire | partner bodies wear the partner's look |  |
| player body and state | `392571767` | character customization GetPreviousState | partner bodies wear the partner's look | yes |
| player body and state | `2682791962` | character customization GetState | partner bodies wear the partner's look | yes |
| player body and state | `2330602565` | character customization GetState(isMale) | partner bodies wear the partner's look | yes |
| player body and state | `1475420904` | controller of an item | partner bodies wear the partner's look |  |
| player body and state | `2825920688` | customizable item appearance change | partner bodies wear the partner's look |  |
| player body and state | `3734582019` | customizable item request step | partner bodies wear the partner's look |  |
| player body and state | `572463144` | customization component | partner bodies wear the partner's look |  |
| player body and state | `3921300146` | customization component | partner bodies wear the partner's look |  |
| player body and state | `3114743990` | customization component | partner bodies wear the partner's look |  |
| player body and state | `1707758916` | customization updater | partner bodies wear the partner's look |  |
| player body and state | `4105184598` | detach animation subgraph from slot | fire and melee subgraphs of our V to partners |  |
| player body and state | `932916046` | garment job (hair tag) | partner bodies wear the partner's look |  |
| player body and state | `3179162639` | head broken-nose controller | partner bodies wear the partner's look |  |
| player body and state | `3484229115` | item job (head, arms) | partner bodies wear the partner's look |  |
| player body and state | `2787715315` | personal link controller | partner bodies wear the partner's look |  |
| player body and state | `4134343353` | target tracker death/defeat handler | our tracker stays on while we are downed | yes |
| NPCs, AI, combat and police | `4040824570` | AI action spot register | NPC copies get the props of their spot |  |
| NPCs, AI, combat and police | `3993835246` | AI action spot unregister | NPC copies get the props of their spot |  |
| NPCs, AI, combat and police | `2099120283` | AICAgent Update (AI tick) | no AI of their own for NPC copies and AV mirrors | yes |
| NPCs, AI, combat and police | `665002914` | AITargetTrackerComponent SetThreatBaseMul | NPCs target partner bodies as players |  |
| NPCs, AI, combat and police | `2565820723` | damage pipeline stage call | co-op and PvP damage claims |  |
| NPCs, AI, combat and police | `300046520` | hit event queue push | co-op and PvP damage claims, hits of copies | yes |
| NPCs, AI, combat and police | `3748802892` | stat pool change | co-op and PvP damage claims |  |
| NPCs, AI, combat and police | `3320125101` | workspot user listener finish | no result written for a dead actor (crash guard) | yes |
| NPCs, AI, combat and police | `1948590813` | workspot user listener report | no result written for a dead actor (crash guard) | yes |
| population and crowd | `322246681` | node streaming reset | a streamed area at far partners (crowd_each) |  |
| population and crowd | `4031648472` | population SpawnShapes | keep circles around partners |  |
| population and crowd | `2558074764` | population entry gate | no NPC spawns where any player looks | yes |
| population and crowd | `1929191932` | population entry gate | no NPC spawns where any player looks | yes |
| population and crowd | `58925250` | population entry gate | no NPC spawns where any player looks | yes |
| population and crowd | `2374048790` | population pass: records to enter the world | no crowd walker pops in at partners | yes |
| population and crowd | `2157779136` | population record removal | why NPCs are taken off (log) |  |
| population and crowd | `3153795579` | population record visibility | NPCs partners see count as seen |  |
| population and crowd | `833690516` | streaming observer frame build | a streamed area at far partners (crowd_each) |  |
| vehicles | `3949215453` | AI command node data creation | a mirror's AI command ends with the host's |  |
| vehicles | `2714310180` | VehicleStreamingHack start | the world does not slow for mirror quest cars | yes |
| vehicles | `390663626` | autopilot end of path | a mirror's path ends by its owner's word | yes |
| vehicles | `3004373527` | autopilot on/off | which quest node drives a car |  |
| vehicles | `2642224723` | entity transforms OnRegisterUpdates | update stages of seated bodies and mirrors |  |
| vehicles | `1295983162` | mounting facility: queue a mount request | partner seats and quest rides |  |
| vehicles | `2933986803` | vehicle ForceMoveTo | only NightCoop moves partners' car mirrors | yes |
| vehicles | `457775029` | vehicle ForceTransform | the autopilot does not place car mirrors | yes |
| vehicles | `3841004136` | vehicle passenger feed | the owner's wheel input on a mirror |  |
| vehicles | `2592348558` | vehicle physics reason mask | mirrors keep their kinematic bit | yes |
| vehicles | `2250642713` | vehicle teleport event | game teleports of quest car mirrors |  |
| quests, facts, scenes and dialogs | `2570850484` | AI command node data delete | led quest nodes (no wake on freed data) |  |
| quests, facts, scenes and dialogs | `1133650948` | braindance ResetRewindableSection | shared braindance timeline |  |
| quests, facts, scenes and dialogs | `223881316` | braindance SetRewindableSectionPlayDirection | shared braindance timeline |  |
| quests, facts, scenes and dialogs | `1511466676` | braindance SetRewindableSectionPlaySpeed | shared braindance timeline |  |
| quests, facts, scenes and dialogs | `2867733787` | character manager quest node | quest kills of copies only by the host (npc_params_host) | yes |
| quests, facts, scenes and dialogs | `311698360` | choice option trigger condition | an option fires at the vote's shared moment | yes |
| quests, facts, scenes and dialogs | `2322147791` | dialog hub input | the dialog vote |  |
| quests, facts, scenes and dialogs | `663036213` | dialog line manager active line | partners' scene skips |  |
| quests, facts, scenes and dialogs | `2707427557` | distance condition instance delete | talk gates |  |
| quests, facts, scenes and dialogs | `2604738521` | interaction manager input | the dialog vote |  |
| quests, facts, scenes and dialogs | `633488107` | journal entry state change | the host's journal to guests |  |
| quests, facts, scenes and dialogs | `2139754534` | quest AND/OR condition instance delete | led quest pauses (led_looks) |  |
| quests, facts, scenes and dialogs | `2832016197` | quest content lock check | a guest's content lock by the host's world | yes |
| quests, facts, scenes and dialogs | `1256328925` | quest fact value changed | the host's facts to guests |  |
| quests, facts, scenes and dialogs | `3773050524` | quest node execute dispatcher | the host's story trace to guests |  |
| quests, facts, scenes and dialogs | `457322231` | quest pause condition node | quest pauses wait for everybody | yes |
| quests, facts, scenes and dialogs | `1467493741` | quest randomizer node run | random quest nodes roll the same for all |  |
| quests, facts, scenes and dialogs | `3319340489` | quest realtime delay activate | realtime delays held at the shared new game |  |
| quests, facts, scenes and dialogs | `4040102541` | quest realtime delay delete | realtime delays held at the shared new game |  |
| quests, facts, scenes and dialogs | `4084932190` | quest realtime delay stop | realtime delays held at the shared new game |  |
| quests, facts, scenes and dialogs | `1352280896` | quest scene node execute | which quest scenes run, matched with partners |  |
| quests, facts, scenes and dialogs | `1893803269` | quest scene node kill | scene ends |  |
| quests, facts, scenes and dialogs | `768416669` | quest scene node restore | scenes restored from a save |  |
| quests, facts, scenes and dialogs | `2955550861` | quest stat condition check | build checks pass if any teammate passes | yes |
| quests, facts, scenes and dialogs | `432612474` | quest street cred tier check | build checks pass if any teammate passes | yes |
| quests, facts, scenes and dialogs | `3063684424` | quest timer fired | realtime delays end at a shared deadline | yes |
| quests, facts, scenes and dialogs | `736895286` | quest zone activator filter | a partner's body does not trigger our quest zones | yes |
| quests, facts, scenes and dialogs | `4079160568` | questScan finished check | braindance clues found by one count for all |  |
| quests, facts, scenes and dialogs | `2497850864` | questUseWorkspot node run | one-body story NPCs | yes |
| quests, facts, scenes and dialogs | `1261442092` | quests system error log | the game's quest errors in our log |  |
| quests, facts, scenes and dialogs | `857943131` | scene choice part builds an InteractionChoice | the dialog vote |  |
| quests, facts, scenes and dialogs | `3519094189` | scene choice part registers conditions | braindance clues found by one count for all |  |
| quests, facts, scenes and dialogs | `1603023693` | scene graph node execute | the host's story trace; random scene nodes |  |
| quests, facts, scenes and dialogs | `1770524544` | scene job delete | led quest nodes |  |
| quests, facts, scenes and dialogs | `1943152583` | scene player-node distance check | a talk stops for all when one walks away |  |
| quests, facts, scenes and dialogs | `1337337713` | scene player-target distance check | a talk stops for all when one walks away |  |
| quests, facts, scenes and dialogs | `913122475` | scene speakers away check | a talk stops for all when one walks away | yes |
| quests, facts, scenes and dialogs | `3187417950` | scene speakers back check | a talk goes on when everybody is back |  |
| quests, facts, scenes and dialogs | `1423842299` | scene system fast forward | scene skip only when everybody may | yes |
| quests, facts, scenes and dialogs | `764613557` | spawn node data delete | led quest nodes (no wake on freed data) |  |
| quests, facts, scenes and dialogs | `3798672630` | teleportation facility Teleport | game teleports of quest cars and NPCs |  |
| quests, facts, scenes and dialogs | `2202144831` | zone condition instance delete | quest pauses wait for everybody |  |
| time and pause | `2989429021` | AudioSystem PauseGameAudio | photo mode does not pause the world's audio | yes |
| time and pause | `3679523410` | photo mode exit restores world time | photo mode does not roll the shared clock back |  |
| time and pause | `4254141749` | quests system: quest delays off | photo mode keeps quest timers running | yes |
| time and pause | `1605312939` | time system SetTimeDilation | photo mode does not freeze the shared world | yes |
| saves and loading | `3014731051` | LoadLastCheckpoint | session rules before the game's own load | yes |
| saves and loading | `2595759321` | LoadModdedSave | session rules before the game's own load | yes |
| saves and loading | `2436965565` | LoadSaveInGame | session rules before the game's own load | yes |
| saves and loading | `3519227454` | add-on files check | a no-Phantom-Liberty start of the host | yes |
| menus and HUD | `3362528776` | character customization RemoveLock | no stuck mirror/Glamdoc state | yes |
| menus and HUD | `1545290538` | menu doll gender choice | the menu doll has our V's body |  |
| menus and HUD | `3187743134` | photo mode face apply | photo mode poses to partners |  |
| menus and HUD | `1333075550` | photo mode show/hide character | photo mode copies of partners |  |
| menus and HUD | `325526536` | splash screen SetState | the intro skip |  |
| world, physics and effects | `297669319` | effect instance start step | our V's explosions and effects to partners |  |
| world, physics and effects | `3180011507` | effect instance tick | our V's explosions and effects to partners |  |
| world, physics and effects | `1292248277` | instanced prop impact handler | props a partner broke break here too |  |
| world, physics and effects | `2140738945` | physics impulse hit dispatcher | props a partner broke break here too |  |
| world, physics and effects | `2470714547` | questPlayEnv SetWeather node | a guest keeps the host's weather | yes |
| world, physics and effects | `1428100262` | random weather change | a guest keeps the host's weather | yes |
| world, physics and effects | `3840414342` | weather advance | a guest keeps the host's weather |  |
| world, physics and effects | `4186127385` | world effect spawn | our V's explosions and effects to partners |  |
| other | `269162020` | AI component event | hang witness of the vehicle move system (log only) |  |

A few more native hooks go by exe offset instead of the address library hash and are not listed here.

### Keys NightCoop reads

NightCoop reads these keys from the OS keyboard while its condition holds; the press is not consumed. A CET hotkey or an Input Loader binding on the same key fires together with NightCoop's action — NightCoop names such bindings in its log. Mods get this list from the SDK (`keysUsed`, `NightCoopSdk.CoopKeys()`).

| Key | Input Loader name | What it does | When | Rebindable |
|---|---|---|---|---|
| PageUp | `IK_PageUp` | hold 1 s: move next to the partner who leads the story | in the world |  |
| PageDown | `IK_PageDown` | hold 1 s: a guest takes the host's story save; the host goes on past a stuck NPC | a story pull or a stuck-NPC hint is on screen |  |
| End | `IK_End` | hold 1 s: the host starts the story without the awaited partners | the story waits for partners |  |
| T | `IK_T` | hold 2 s: pass out and wake in a safe place | downed |  |
| F | `IK_F` | hold 1 s: help a downed partner up; take your seat of the host's quest ride; vote | at a downed partner, at a ride's door, a vote is open |  |
| Enter | `IK_Enter` | vote for the selected row | a vote is open |  |
| Up | `IK_Up` | move the selection in NightCoop's vote window | a vote is open in NightCoop's window |  |
| Down | `IK_Down` | move the selection in NightCoop's vote window | a vote is open in NightCoop's window |  |
| NumPad1 | `IK_NumPad1` | vote for row 1 (NumPad1..NumPad9: rows 1..9) | a vote is open in NightCoop's window |  |
| 1 | `IK_1` | apply quickhack 1 of the wheel (1..8: rows 1..8, the default set) | the quickhack wheel is on screen (quickhack_keys) | yes (co-op menu) |
| F1 | `IK_F1` | apply quickhack 1 (the F-keys set: F1-F4, F6-F8, F10) | the quickhack wheel is on screen and the F-keys set is chosen | yes (co-op menu) |
| P | `IK_P` | next pose of a partner's photo copy (Shift+P: previous) | photo mode, photo_copies |  |
| G | `IK_G` | camera orbit around the photo copy (Shift+G: back) | photo mode, photo_copies |  |
| Delete | `IK_Delete` | remove the selected photo copy | photo mode, photo_copies |  |

### Popular mods with a known overlap

NightCoop recognises these by their folder or file name and writes the line to its log.

| Mod | Area | What it does and what co-op relies on there |
|---|---|---|
| PhotoMode-EX | menus and HUD | patches a byte inside PhotoModeSystem_ProcessAttribute (the photo mode NPC list limit) and replaces gameuiPhotoModeMenuController / PhotoModePlayerEntityComponent functions; NightCoop's photo copies of partners (photo_copies) and live photo mode menu items (photo_live) rely on both — the byte patch is not seen by NightCoop's checks |
| Equipment-EX | player body and state | rewrites placementSlots of clothing records (ApplyMapping) and overrides photo mode functions; NightCoop sends partners' looks by OutfitSlots.* and placementSlots[0] — a partner without the same mod sees other slots |
| Audioware | time and pause | hooks the time system, SaveHandlingController and InkMenuScenario natively; a hook on the same entry as NightCoop's (photo mode time, game loads) is seen at run time, others are not |
| RadioExt | vehicles | overrides VehicleObject.GetCurrentRadioIndex / WasRadioReceiverPlaying, VehicleComponent.OnRadioToggleEvent and PocketRadio functions NightCoop reads to share the car radio: a partner without RadioExt hears another station |
| Time Dilation Overhaul | time and pause | wraps TimeDilationHelper.SetTimeDilation*; NightCoop deliberately keeps SetTimeDilationWithProfile off in co-op (slow motion would slow the shared world), so the mod's slow motion is not shared |
| Immersive Timeskip | time and pause | wraps TimeskipGameController.Apply / OnUpdate; NightCoop wraps gameuiTimeskipGameController.Apply for the guests' time skip rules — fine while the wrapper calls wrappedMethod (NightCoop checks that at run time) |
| Quickhack Hotkeys | menus and HUD | replaces QuickhacksListGameController.SetVisibility, wraps HUDManager.RegisterToInput and binds keys on the quickhack wheel; NightCoop's own quickhack keys (digits 1-8 by default) and its HUDManager.JumpToNextTarget wrap work on the same wheel — keep one of them (NightCoop: quickhack_keys off) |
| Appearance Menu Mod | player body and state | observes PlayerPuppet.OnGameAttached / OnAction, overrides TryFastTravel, observes DamageSystem.ProcessRagdollHit and FastTravelSystem.OnLoadingScreenFinished; partners' bodies are PlayerPuppets in your game, AMM may treat them as your V |
| Native Settings UI | menus and HUD | overrides gameuiMenuItemListGameController.AddMenuItem and observes OnMenuItemActivated; NightCoop adds its co-op menu item through the same functions — fine while the override calls the original |
| Mod Settings | menus and HUD | replaces MenuScenario_PauseMenu / DeathMenu / SingleplayerMenu; NightCoop's co-op menu entry and its back step (MenuScenario_PauseMenu.OnBack) live there |
| Wannabe Edgerunner | NPCs, AI, combat and police | hooks PreventionSpawnSystem.SpawnRequestFinished; the host spawns guests' police through it (police_host_only) |
| Auto Drive Enhanced | NPCs, AI, combat and police | hooks PreventionSystem.HeatPipeline; NightCoop leads guests' police by the host (police_host_only) |
| Limited HUD | menus and HUD | wraps MinimapContainerController and HUD functions; NightCoop's partner pins (CreateMappinUIProfile, ComputeRootState) are on the same minimap |
| Better Minimap | menus and HUD | replaces minimap drawing natively; NightCoop's partner pins are on the same minimap |
| Improved Minimap Zoom | menus and HUD | wraps MinimapContainerController; NightCoop's partner pins are on the same minimap |
| Custom Map Markers | menus and HUD | wraps map pin controllers; NightCoop's partner pins use the same mappin classes |
<!-- hook-tables:end -->
