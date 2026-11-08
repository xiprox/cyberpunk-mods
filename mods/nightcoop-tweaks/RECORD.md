# Record

What we found and decided while building NightCoop Tweaks, newest entry first.
[README.md](README.md) says what the tweaks do; this file says why they're that way.

"User" marks what the user saw in the game.
Versions on this PC: Cyberpunk 2077 (CET reports 3.0.88.46235), NightCoop build bacb705, Cyber Engine Tweaks 1.38.1, Codeware installed.

Checked in the game on 2026-10-29: the "[F] Interact" prompt comes up next to a partner, F opens the menu, and a send shows the progress bar (user).
Not yet checked in the game: the 1 m range, F and Enter on a partner in the phone's Contacts (partners show there, user), whether the mouse wheel moves the selection, whether the quantity slider opens and closes in the world, whether a transfer arrives, whether map pins give nicknames, and whether NightCoop's dialog votes leave our choice list alone.
CET writes small logs out only now and then, so during a session the mod's log is empty: the NightCoop Tweaks window's Diagnostics section shows what the partner menu sees, which keys reach the mod, and any error.

## 2026-11-01: A partner in first-person stands on a bike

Anyone riding a bike in first-person looks like they stand to the others, and sits in third-person (user, on all three players). NightCoop's reports agree: "body at the handlebars of a bike" gives hands at 0.98 m and none of the frames collapsed at the seat, against 0.03 m and nearly all of them. It looked like one player's problem because the user rides in first-person and the friends in third.
NightCoop puts a body on a bike on the graph's third-person branch whatever the rider's camera (its switches `bike_tpp_all`, `bike_rider_tpp`). `NightCoopAnimTap(20)` on the rider, across a switch from third-person to first, shows what fired once: the wrappers `player_fpp_head` = 1 and `player_tpp_head` = 0, `TPPRepresentation` (NightCoop keeps that from the body), and two camera reset events. At least some of a body's animation sets are gated on `player_tpp_head`: NightCoop's "body builder" line drops a security-cam set "on player_tpp_head". So the bet is that the wrapper takes the third-person bike clips away and the graph falls back to a stand.
This fits what looked odd: after a game restart the user sat in first-person, not having switched camera yet, so the wrappers hadn't been sent. A body also sits only some seconds after a switch back to third-person, as an npc copy "stands in its seat workspot" while its clip sets load. It's still a bet: the wrapper count on a body didn't change at the moment one sat again, seconds later, and the tap's report gives features only as counts, so an input inside a feature would not show.
`tweaks/bikeseat` writes both wrappers back on every other `PlayerPuppet`. A body that never had them changed sits fine on foot, so this should leave everything else alone. The other way, turning those two switches off, changes every rider, and NightCoop's text warns of a "spine rebuilt for the camera".
First try, 23:57 that night, ten times a second on all three machines (the log collector's Mods tab brings this mod to the friends, and each reloaded): "still broken" for everyone (user).
NightCoop's pose lines say it helped but not enough. The user's first-person samples on the other two machines went from 270 standing and 9 sitting to 13 standing and 49 sitting (hips over or under 0.5 m, about every 5 s). What's left comes in stretches of about 5 to 25 s after a camera switch, getting on, or a new body, and then the body sits: 23:57:42 to 23:57:47 after a switch, 00:02:25 to 00:02:46 and 00:04:54 to 00:05:14 after a new body. Short rides and switching back and forth are nearly all stretch, which may be what everyone saw. The fall to about a fifth is the best evidence for the wrappers so far, though it doesn't name them alone.
So 0.1.1 writes them every frame, in case the stretch is the clips loading again after even a moment with the wrapper off, and looks for a missing body every second, not every three.
Checked in the game on 2026-11-02: it "works seemingly perfectly" (user, after testing with the friends). From 0.1.1 loading at 00:38:41 on the user's clock to 00:44:47, NightCoop's pose lines on all three machines have first-person riders 100 sitting and 0 standing, all three players among them, and third-person riders 63 and 0; 4 of the 107 samples with no known camera stand. The lines come about every 5 s, so a shorter stand wouldn't show. Frame times didn't rise over those 6 minutes (33.4 to 33.4 ms, 21.7 to 18.9, 11.3 to 9.6).
That the clips load again after a moment with the wrapper off is still inferred; the logs don't show it directly.
Not yet checked in the game: how long the look through `Game.GetEntityList` takes, and a longer session.

## 2026-11-01: The phone opens the partner menu in a car

The menu was off in every vehicle because F also gets out of the car, an assumption nobody had checked. The game's script (`vehicleTransition.script`) only gets out once F is held for 0.3 s, and our pick is a tap, so the user asked to loosen it.
From the phone the menu now opens in a car and stays open there; a list opened by walking up still closes on getting in, and the walk-up prompt stays off, since partners in their seats are all within reach and it would come up at every glance at them.
In a car a pick has to end within 0.25 s, not the usual 0.35 s, so one press can't both pick and start getting out; Enter picks there too.
F and the scroll keys do reach the mod in a car: every vehicle input context includes `InteractionActions` through `UIExploration`. A quick F does one other thing in a car, only with a weapon drawn in car combat: it puts the weapon away.
A ride of the story keeps the menu off (the player's `VehicleScene` status effect tag, the one the game's `IsExitVehicleBlocked` reads), so our list can't share F with a scene's "Skip Ride".
The first try refused from the phone in a car: "in a workspot (seated or leaning)" (user). A car's seat is a workspot to the game (`IsActorInWorkspot`), which the vehicle rule used to hide by coming first, so the seat rule now leaves cars alone.
Not yet checked in the game, including whether the car keeps moving behind the amount slider.

## 2026-10-29: F on a ride's dialog choice also skipped the ride, by NightCoop, not us

In Panam's car, F on "How much do you know about Rocky Ridge?" also took the "Skip Ride [F]" prompt, and the ride jumped ahead (user).
NightCoop's log has both from the one press, at 21:31:10.995: "dialog vote #76: we vote for option 4 ... (our press)" and "scene skip: we skip the cutscene of scene 0x14fa37456a18f706 (node 1753: the player's "cancel")", then the car moved 853 m by a quest teleport. NightCoop takes the choice press for its vote and plays it to the game later ("press replayed through the interaction manager"), so the press itself was left to the ride's skip, which shares F.
Our mod had no part: in a vehicle the partner menu is off and writes no choice list, and its key listener only listens (`ItemQuantityPickerController.OnAction` consumes nothing). The game's own scene skip is Y (`SceneFastForward`), unchanged in the user's key bindings, so "Skip Ride" on F is the scene's own option. For NightCoop's developer to fix.

## 2026-10-29: No prompt in scenes or seats

In a scene (V seated with Johnny, no HUD) the "[F] Interact" prompt came up for B, because NightCoop stands every partner on our spot during one (user).
The game keeps the scene's tier in the player's state machine blackboard (`PlayerStateMachine.HighLevel`, `gamePSMHighLevel`: tier 1 is full gameplay, 2 a staged walk, 3 limited, 4 and 5 cinematics), and its own code holds gameplay back from tier 2 (the pocket radio, the forced holster), so the partner menu is off from tier 2 to 5, and in a workspot (`WorkspotGameSystem.IsActorInWorkspot`, a seat or a lean), where F can be the way out.
Diagnostics names the tier when it's off for one.
Checked in the game on 2026-10-30: the menu went off for tiers 2 to 5 through the evening (the user's log).
That night the prompt came up again in the scene where Scorpion's drone scouts for Panam (q104) (user). NightCoop's log has our player "controls a device ... (plays as V, scene tier 1)" from 20:15:31 to 20:16:40, out of the car, with both partners working the drone from the same spot: flying a drone is tier 1, so the tier check let it through. The game keeps that in the same blackboard, `PlayerStateMachine.IsControllingDevice` (a drone, camera or turret) and `IsUIZoomDevice` (zoomed into a device's screen), and turns the phone off for either (`PhoneSystem.IsBlockedByBlackboard`), so the partner menu is off for either too.
The user suggested a backstop that would have caught both: a partner on our exact spot. NightCoop's log shows it in the drone scene, "the body of peer 0 stands inside our player (0.0 m: one spawn point for both) — hidden until one of us steps away", and the same for peer 1, and the prompt even favoured such a partner: the facing check took one closer than 0.2 m as faced head-on. So partners within 0.3 m are now left out of the prompt (Diagnostics marks them "on our spot, left out"), whatever the scene's tier or flags say; two people facing each other stand farther apart than that, and a partner walked into steps out of it.
Our own mod's log had nothing from then: CET had last written it at 19:55, and the log collector skips our junctioned mod folder, so its copy of that log isn't collected; NightCoop's log was the record.

## 2026-10-29: A nickname goes to a partner only when they stand apart

Both partners showed as "B" in the phone's Contacts, where one is Bleack (user).
The mod's log shows how: "peer 2 is B" while peer 0 was B, and later "peer 0 is Bleack" and "peer 3 is Bleack" in the same second. Each partner took the name of the nearest pin within 2.5 m, so with B's pin missing from the lists for a moment and B standing by Bleack, both took Bleack's; and names, once learned, were never looked at again.
The pins carry nothing that ties them to a peer (`IMappin.GetEntityID` gives the body, which nothing maps to a peer id; `NightCoopRemoteInfo` has only peer, position, yaw, speed and tick), so pairing stays by position, made strict:
a pin names a partner only when no other partner is within 2.5 m of it and no pin of another name is within 2.5 m of them, so partners close together are left until they part; a new pairing is taken once two looks in a row, 2 s apart, agree, since a pin can trail a moving body; a nickname is one partner's, and whoever had it by an earlier mix-up loses it (back to "Peer N") when its owner is paired again; and the pairing runs every 2 s for as long as there are partners, so a wrong name is put right.
An offline run of `core/nightcoop.lua` with the game stubbed went through partners together, a trailing pin, B beside Bleack's lone pin, parting, and an old mix-up, and gave the right names each time; not yet checked in the game.

## 2026-10-29: Partners are contacts in the phone, and calling one opens their partner menu

The phone's Contacts tab (`NewHudPhoneGameController`, the 2.x phone) is filled in `SetScreenType` from `MessengerUtils.GetCallableAndNonEmptyContacts`, the journal's contacts as `ContactData`.
Overriding that function failed in the game: CET answered "Function GetCallableAndNonEmptyContacts in class MessengerUtils does not exist" (user), because a script's static function isn't a member of its class but a global named `MessengerUtils::GetCallableAndNonEmptyContacts;JournalManager` (NightCoop's dump lists it as `G`), which CET's Observe and Override can't reach. `tools/check.py` now checks every hook against the class's member functions.
So `core/phone.lua` observes `SetScreenType` instead and, on the Contacts tab, adds one `ContactData` per partner NightCoop reports (type `Contact`, callable, preview "NightCoop partner", an id `nightcoop_peer_<peer>` and a negative hash, clear of the journal's); the game already mixes a script-made entry into its contact lists, the "Show all" item.
Appending them to the list's data source (`AppendItem`) after it was filled added them, by Diagnostics, but they didn't show (user), so the list is filled again with `PopulateListData`, the game's contacts and ours, the way `SetScreenType` fills it; that sorts the partners by name among the callable contacts.
F in the phone's list is the `click` action (F, left mouse, X on a pad), which on the Contacts tab calls `CallContact`; the override sees our id, closes the phone with `CloseContactList` and hands the partner to `PartnerMenu.OpenFor`, before the game builds a holocall, so NightCoop's call sharing ("any contact, shared dial and answer") never sees a call.
The partner menu waits for the phone to close (`UI_ComDevice.ContactsActive`) and opens the partner's list with no prompt and no walking-off rule; in combat it says so on screen instead (in a vehicle too, until 2026-11-01, above).
The first try opened for one partner but not the other: for B, the host 59 m away, Diagnostics said the menu was open for them, from afar, while no list was on the dialog blackboard (user). Something took the list off as the phone closed; what, and why for that partner, is unknown. So the menu now waits half a second after the phone closes, and keeps the list it shows and puts it back whenever it goes missing while open (Diagnostics counts how often).
The phone's Call key is the `click` action, bound to F, left mouse and pad X but not Enter, so Enter on the game's own contacts does nothing; the user wanted Enter on a partner too. The phone listens for its keys on the player (`RegisterInputListener`), which doesn't send it Enter at all, so `core/phone.lua` reads Enter itself, as `UI_Apply` or `ChoiceApply` with the Enter key behind it, and calls the selected partner when the phone is up on the Contacts tab. Whether those actions reach a listener on the player while the phone is up is untested; Diagnostics' "Keys heard" and "partner calls ... by Enter" will say.
Reading keys moved out of `core/choices.lua` into `core/input.lua`, one listener on the player for every action any part asks for, so the phone and the choice list don't each register one.
In our lists Enter picks, since `ChoiceApply` is bound to F, Enter and pad X.
A real chat thread with the partner was ruled out: the messenger draws threads from journal entries a mod can't make at runtime, and NightCoop wraps `MessengerDialogViewController.ActivateReply` to send every chat reply to the host.

## 2026-10-29: The payee's glowing eyes are parked

In the story's payments the payee's eyes glow orange and flicker while the bar runs (user), so on a send our game would play that on its own copy of the partner's body, needing nothing from their side.
The game's scripts never name it (quest scenes play it), so `core/effects.lua` lists the effects of what we look at (an entity's `entEffectSpawnerComponent.effectDescs`) in Diagnostics and plays one from the console, to find its name on an NPC and see whether a partner's body has it; NightCoop adds effects to partner bodies for its Sandevistan trail, so a missing one could be added the same way.
The user parked it before the name was found.

## 2026-10-29: A transfer shows as the game's progress bar

The user wanted the "transaction in progress" bar from the story's payments in place of the on-screen message.
It's the HUD progress bar quests and quickhack uploads use (`HUDProgressBarController`), drawn from the `UI_HUDProgressBar` blackboard, with a money look (the eddies icon) for `gameSimpleMessageType.Money`.
`core/progressbar.lua` sets it in the game's own order (`rpgManager.script`): Active, header, the texts, the message type last, so our own header keeps the money look, which the controller otherwise picks only for two of the game's headers.
The bar follows the real transfer: it fills while NightCoop's request is out and completes once our balance drops, which is when the host accepted it and NightCoop debited us; it fails at once on a refusal, or after 8 seconds without an answer.
It doesn't sync to partners (NightCoop only reads its controller to place its own status line), so only the sender sees it, as in the story.
When a quest's bar is already up, the on-screen message comes back instead.

## 2026-10-29: The prompt comes up within 1 m of a partner we face

At first the prompt only came up when the game's look-at target was the partner's body, which needs the crosshair on them, and it rarely showed (user).
It now also comes up when the camera faces a partner within 20 degrees across the ground; a partner in another world has no body here, but a prompt for them still works, since money goes through the host.
The range was 3 m, and the user found that too far: it's 1 m now.
It stays off in combat, because the game treats our list as a conversation and holds back consumables and grenades while one is up.

## 2026-10-29: F reaches the menu as ChoiceApply or Choice1, read with ListenerAction's static functions

The prompt came up, but F did nothing (user).
Two things changed at once and F works since (user), so which one it was is unknown: the handler read the action as `action:GetName(action)`, while CET 1.38 knows `ListenerAction` (native `gameinputScriptListenerAction`) with static functions, now called as `ListenerAction.GetName(action)` with the old form as a fallback; and the mod listened only for `ChoiceApply`, which NightCoop watches for its dialog votes, and now also listens for `Choice1` (and `Choice1_Release`), what F sends for the game's own "[F] Open" prompts.
One F comes as both, so the first press and release count once.
The Diagnostics section's "Keys heard" line names the last action the mod got.

## 2026-10-28: One mod of many tweaks, on a shared core

The user plans more NightCoop tweaks, so the mod is one CET mod with a folder per tweak under `tweaks/` and what they share in `core/`, rather than a CET mod per tweak: the partner's "[F] Interact" list has to be one list, and two mods would each write their own to the dialog blackboard and read F twice.
Tweaks add entries to that list through `core/partnermenu.lua` and draw a section of one CET window.
`init.lua` runs every tweak's hooks in `pcall`, and a hook that throws stays off until Reload All Mods, since a tweak that fails every frame would otherwise stop the ones after it and fill the log.

## 2026-10-28: Partner nicknames come from NightCoop's map pins

No NightCoop native gives a partner's nickname: `NightCoopStatus` has only our own peer id, `NightCoopRemoteInfo(i)` gives `peer=N pos=(x, y, z) ...`, and the status natives that mention peers (`NightCoopSessionStatus`, `NightCoopMenu`, `NightCoopMarkers("status")`) print states, not peer-to-name pairs (read in their disassembly).
NightCoop's logs do pair them, "map pin #1 for Bleack (peer 4) on the body 0x9de835", and that pin is the way in: NightCoop registers one per partner body with the game's `MappinSystem`, variant `CPO_RemotePlayerVariant`, and sets its `debugCaption` to the nickname (its DLL calls `SetMappinDebugCaption`).
The game reads a script-set caption back through `IMappin.GetDisplayName()` (`CyberspaceMappinController` does), so `core/nightcoop.lua` lists the remote-player pins, takes their names, and pairs each with the peer NightCoop places within 2.5 m of it across the ground (made strict on 2026-10-29, above).
Names stay for the session, since a partner who leaves our world loses their pin.
A partner never seen in our world, or with NightCoop's player markers off, stays "Peer N".
If pins turn out to have no caption, the fallback is NightCoop's floating name tags: an ink layer `NightCoopPlayerMarkers` in the HUD with a `NightCoopPlayerMarker` per partner holding a name and a distance text, though nothing on them says which peer they belong to.

## 2026-10-28: The custom amount is the game's own quantity popup

The slider the game shows for dropping or selling a stack (`ItemQuantityPickerController`, widget `base\gameplay\gui\widgets\notifications\item_quantity_picker.inkwidget`) is opened with `ShowGameNotification` and a `QuantityPickerPopupData`, as the backpack does.
It's shown from `PopupsManager`, found on Codeware's `inkHUDLayer`, which shows the game's own in-world popups (the car color picker, the codex) with `isBlocking` and `useCursor`; the game's dialog widget controller is the fallback.
`TransferToPlayer` hides the price, and the popup's item name and button text are set to the partner and "Send" after its `SetData`.
The popup stays up while its notification token is held: the backpack takes it down by dropping the token in its close callback, so `core/quantity.lua` does the same.
CET Lua can't be a callback target, so the token's listener is a detached `gameNotificationsTest`, a sample class the game never uses whose `OnResponse` only clears its own field, and `core/quantity.lua` observes that `OnResponse`.

## 2026-10-28: "[F] Interact" is our own list on the game's dialog blackboard

The game's dialog widget draws whatever `DialogChoiceHubs` holds on the `UIInteractions` blackboard, and the player's state machine treats a non-empty list as a conversation (`AreChoiceHubsActive`), so the mouse wheel doesn't switch weapons while ours is up.
`core/choices.lua` writes the list, the active hub id and the selected index there, puts the list back if something clears it, and steps aside when the game writes a conversation of its own.
The game's interaction system doesn't know our list, so F and scrolling are read from `ChoiceApply`, `ChoiceScrollUp` and `ChoiceScrollDown`, which `Exploration` includes on foot.
The listener is a detached `ItemQuantityPickerController`, whose `OnAction` reacts only to `mouse_wheel`, so our actions run no game code.
`UI_MoveUp` and `UI_MoveDown` are also bound to W, S, Q and E, so only the wheel, the arrow keys and the d-pad scroll.
A pick is a tap of F of 0.35 s at most, because NightCoop helps a downed partner up on a held F.
The prompt shows when `TargetingSystem.GetLookAtObject` gives a body within 3 m that stands within 1.5 m of NightCoop's position for a peer, so a partner in another world, with no body here, gets no prompt.
NightCoop's dialog votes read the same blackboard and the dialog widget's active hub and selection; they're meant for scene choices, but that's unchecked.

## 2026-10-28: Money goes through NightCoop's own item transfer

`NightCoopGiveItem(record: String, quantity: Int32, peer: Int32) -> String` (signature read from NightCoop's `PostRegisterTypes`) offers items to a peer; the host accepts, the sender is debited, the recipient is credited, and both sides confirm, so an item can be lost but never duplicated.
Eddies are the item `Items.money`.
NightCoop refuses a quantity outside 1 to 9,999 and a transfer to ourselves, so larger amounts go as several transfers.
It checks each request against the balance but debits later, so several requests in a row could each pass; `tweaks/sendmoney/money.lua` checks the whole amount against the balance first.
A successful call answers "inventory: transfer 0x... requested for peer N".

## 2026-10-28: How NightCoop and the game are read

NightCoop is a closed-source RED4ext plugin with no API documentation.
Its script natives are registered in `PostRegisterTypes`, and `tools/re/ncre.py natives` reads their names and signatures from the disassembly ([docs/nightcoop-natives.txt](docs/nightcoop-natives.txt)); CET calls them as `Game.<Name>(...)`.
NightCoop also exports a C interface, `NightCoopAddonApi`, for one native addon at a time; it's undocumented and these tweaks don't need it.
For the game, REDmod ships the script sources of this exact version in `<game>\tools\redmod\scripts`, and NightCoop dumps every class, property and function into `rtti-names-*.txt` next to its DLL.
