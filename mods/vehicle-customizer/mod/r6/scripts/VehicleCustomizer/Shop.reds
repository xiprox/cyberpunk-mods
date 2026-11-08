// Vehicle Customizer: the customization screen's state and actions (vehicle-customizer/RECORD.md, UX.md).
// F7 opens and closes the screen (Screen.reds) anywhere in the world. It works on the car V is in, else the one V
// looks at, else the nearest of the shop's cars within 25 m, and keeps that car while the screen is closed. Every
// choice goes through the engine, so it shows on the car at once and is saved; an undo list and the build as it was
// when first opened this session make trying things free. Buying hands out one of a model's five copies that the
// player, or a player in the session, doesn't own yet; two players with the same copy share one car, as with a game
// car (see "which copies are taken").
// Until there's a shop in the world, this is the whole shop: no prices, no stand, no robot arms.
module VehicleCustomizer
import Codeware.UI.*

// The key that opens the screen: a key picker in Mod Settings (Settings, Mods, Vehicle Customizer) where Mod
// Settings is installed, else F7 (user, 2026-11-06). The fields compile without Mod Settings; only listening needs it.
public class VCSettings extends IScriptable {
    @runtimeProperty("ModSettings.mod", "Vehicle Customizer")
    @runtimeProperty("ModSettings.displayName", "Open the customizer")
    @runtimeProperty("ModSettings.description", "The key that opens and closes the customization screen, anywhere in the world.")
    public let openKey: EInputKey = EInputKey.IK_F7;
}

@if(ModuleExists("ModSettingsModule"))
public func VCListenToSettings(settings: ref<VCSettings>, on: Bool) {
    if on {
        ModSettings.RegisterListenerToClass(settings);
    } else {
        ModSettings.UnregisterListenerToClass(settings);
    }
}

@if(!ModuleExists("ModSettingsModule"))
public func VCListenToSettings(settings: ref<VCSettings>, on: Bool) {}

public class VCShop extends ScriptableSystem {
    private let m_settings: ref<VCSettings>;
    private let m_record: TweakDBID;
    private let m_screen: ref<VCScreen>;
    private let m_message: String;
    private let m_foreign: String;
    // Undo: each car's build before each change, newest last.
    private let m_undoRecords: array<TweakDBID>;
    private let m_undoTexts: array<String>;
    // Each car's build as it was when first opened this session.
    private let m_startRecords: array<TweakDBID>;
    private let m_startTexts: array<String>;
    private let m_callAgain: TweakDBID;
    // In a session: partners' lists of the shop cars they own, by their key in the session's state, and whether ours
    // needs putting in (see "which copies are taken").
    private let m_ownKeys: array<String>;
    private let m_ownLists: array<String>;
    private let m_ownDirty: Bool;

    // Where the screen was, kept between openings.
    public let tab: Int32;
    public let styleShown: CName;
    public let slotIndex: Int32;
    public let paintTarget: CName;
    public let kitIndex: Int32;
    public let kitPart: Int32;
    public let fine: Bool;
    public let axle: CName;
    // The Wheels tab's list: n"tire" (and the size and width with it) or n"rim".
    public let wheelPart: CName;
    public let garagePick: CName;
    public let garageModel: CName;
    public let garageStyle: CName;
    public let garageCar: CName;
    public let viewExtra: Float;
    public let lastView: Int32;
    // How the screen opens, chosen in the Service tab while we find what freezes the world behind it (2026-11-06):
    // 1 the CrystalCoat picker's way exactly, 2 the picker's without blur, 3 blocking with no slow motion or blur,
    // 4 Codeware's own in-game popup.
    public let popupMode: Int32;

    public static func Get(game: GameInstance) -> ref<VCShop> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(n"VehicleCustomizer.VCShop") as VCShop;
    }

    private func OnAttach() {
        this.axle = n"all";
        this.wheelPart = n"rim";
        this.kitPart = -1;
        this.paintTarget = n"car";
        this.garagePick = n"mine";
        this.popupMode = 1;
        this.m_settings = new VCSettings();
        VCListenToSettings(this.m_settings, true);
        GameInstance.GetCallbackSystem().RegisterCallback(n"Input/Key", this, n"OnKey");
    }

    private func OnDetach() {
        GameInstance.GetCallbackSystem().UnregisterCallback(n"Input/Key", this);
        VCListenToSettings(this.m_settings, false);
    }

    // The open key from Mod Settings; F7 when it's unbound or Mod Settings isn't there.
    public func OpenKey() -> EInputKey {
        if !IsDefined(this.m_settings) || Equals(this.m_settings.openKey, EInputKey.IK_None) {
            return EInputKey.IK_F7;
        }
        return this.m_settings.openKey;
    }

    // The open key as the screen writes it: IK_F7 becomes F7.
    public func OpenKeyName() -> String {
        let name = NameToString(EnumValueToName(n"EInputKey", Cast<Int64>(EnumInt(this.OpenKey()))));
        return StrBeginsWith(name, "IK_") ? StrRight(name, StrLen(name) - 3) : name;
    }

    // The open key opens and closes; Ctrl+Z undoes while it's open. Esc closes too (the popup's own cancel).
    private cb func OnKey(event: ref<KeyInputEvent>) {
        if !Equals(event.GetAction(), EInputAction.IACT_Press) {
            return;
        }
        let key = event.GetKey();
        if Equals(key, this.OpenKey()) {
            if this.IsOpen() {
                this.m_screen.Close();
            } else {
                this.Open();
            }
        } else if Equals(key, EInputKey.IK_Z) && event.IsControlDown() && this.IsOpen() {
            this.Undo();
            this.RefreshScreen();
        }
    }

    public func IsOpen() -> Bool {
        return IsDefined(this.m_screen) && this.m_screen.IsShowing();
    }

    public func Open() {
        let game = this.GetGameInstance();
        let player = GetPlayer(game);
        if !IsDefined(player) || player.IsDead() {
            return;
        }
        let ui = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UI_System);
        if IsDefined(ui) && ui.GetBool(GetAllBlackboardDefs().UI_System.IsInMenu) {
            return;
        }
        let manager = CustomPopupManager.GetInstance();
        if !IsDefined(manager) || !manager.IsInitialized() {
            return;
        }
        this.PickTarget();
        if !IsDefined(this.Car()) && this.tab != 5 {
            this.tab = 6;
        }
        let screen = new VCScreen();
        screen.SetShop(this);
        this.m_screen = screen;
        manager.ShowPopup(screen);
    }

    // Closes the screen if it's open (the test job "buy").
    public func CloseScreen() {
        if this.IsOpen() {
            this.m_screen.Close();
        }
    }

    public func ScreenClosed(screen: ref<VCScreen>) {
        if Equals(this.m_screen, screen) {
            this.m_screen = null;
        }
    }

    public func RefreshScreen() {
        if this.IsOpen() {
            this.m_screen.Refresh();
        }
    }

    // --- the car being worked on ---

    public func Engine() -> ref<VCEngine> {
        return VCEngine.Get(this.GetGameInstance());
    }

    public func Record() -> TweakDBID {
        return this.m_record;
    }

    public func Car() -> ref<VehicleObject> {
        let engine = this.Engine();
        if !TDBID.IsValid(this.m_record) || !IsDefined(engine) {
            return null;
        }
        return engine.VehicleOf(this.m_record);
    }

    public func Catalog() -> CName {
        let engine = this.Engine();
        return TDBID.IsValid(this.m_record) && IsDefined(engine) ? engine.CatalogOf(this.m_record) : n"";
    }

    // The car V is in when it isn't one of the shop's, to say so.
    public func Foreign() -> String {
        return this.m_foreign;
    }

    public func Message() -> String {
        return this.m_message;
    }

    public func Say(text: String) {
        this.m_message = text;
    }

    // The build the car wears: a partner's, for their car; else ours, saved.
    public func BuildText() -> String {
        let engine = this.Engine();
        let vehicle = this.Car();
        if IsDefined(vehicle) {
            return engine.BuildTextOf(vehicle);
        }
        return TDBID.IsValid(this.m_record) ? engine.GetBuildText(this.m_record) : "";
    }

    // The look the build stands on, without the twin suffix.
    public func CurrentLook() -> String {
        let build = VCBuild.Parse(this.BuildText());
        if IsNameValid(build.look) {
            return NameToString(build.look);
        }
        let vehicle = this.Car();
        return IsDefined(vehicle) ? VCData.BaseLook(NameToString(vehicle.GetCurrentAppearanceName())) : "";
    }

    public func PickTarget() {
        let game = this.GetGameInstance();
        let engine = this.Engine();
        let player = GetPlayer(game);
        this.m_foreign = "";
        if !IsDefined(engine) || !IsDefined(player) {
            return;
        }
        let mounted = player.GetMountedVehicle();
        if IsDefined(mounted) {
            if engine.IsOurs(mounted.GetRecordID()) {
                this.SetTarget(mounted.GetRecordID());
                return;
            }
            this.m_foreign = mounted.GetDisplayName();
        }
        let looked = GameInstance.GetTargetingSystem(game).GetLookAtObject(player, false, false) as VehicleObject;
        if IsDefined(looked) && engine.IsOurs(looked.GetRecordID()) {
            this.SetTarget(looked.GetRecordID());
            return;
        }
        let current = this.Car();
        if IsDefined(current) && Vector4.Distance(current.GetWorldPosition(), player.GetWorldPosition()) < 40.0 {
            return;
        }
        let near = engine.NearestOurs(player.GetWorldPosition(), 25.0);
        if IsDefined(near) {
            this.SetTarget(near.GetRecordID());
        }
    }

    public func SetTarget(record: TweakDBID) {
        if !(record == this.m_record) {
            this.m_record = record;
            this.slotIndex = 0;
            this.kitIndex = 0;
            this.kitPart = -1;
            this.styleShown = n"";
            this.paintTarget = n"car";
        }
        if ArrayFindFirst(this.m_startRecords, record) < 0 {
            let text = this.Engine().GetBuildText(record);
            // As for undo: no build yet is kept as the car's look, so "undo this visit" brings the style back too.
            if StrLen(text) == 0 && IsDefined(this.Car()) {
                text = "look=" + this.CurrentLook();
            }
            ArrayPush(this.m_startRecords, record);
            ArrayPush(this.m_startTexts, text);
        }
    }

    // The car to change, after keeping its build for undo; none for a partner's car or no car.
    private func Changing() -> ref<VehicleObject> {
        let vehicle = this.Car();
        if !IsDefined(vehicle) {
            this.Say("No car here to work on. Call it from the garage tab.");
            return null;
        }
        let text = this.BuildText();
        // A car with no build yet is kept as its look: an empty build means "as the car is now", so undoing the
        // first change (a new style) kept the new style (tool test, 2026-11-07).
        if StrLen(text) == 0 {
            text = "look=" + this.CurrentLook();
        }
        let n = ArraySize(this.m_undoTexts);
        let same = false;
        if n > 0 {
            same = this.m_undoRecords[n - 1] == this.m_record && Equals(this.m_undoTexts[n - 1], text);
        }
        if !same {
            ArrayPush(this.m_undoRecords, this.m_record);
            ArrayPush(this.m_undoTexts, text);
            if ArraySize(this.m_undoTexts) > 100 {
                ArrayErase(this.m_undoRecords, 0);
                ArrayErase(this.m_undoTexts, 0);
            }
        }
        return vehicle;
    }

    // --- choices ---

    public func ChooseLook(look: CName, label: String) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().ChooseLook(vehicle, look);
            this.Say("Now " + label + ".");
        }
    }

    public func ChooseOption(slot: CName, option: CName, label: String) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().ChooseOption(vehicle, slot, option);
            this.Say("Trying " + label + ".");
        }
    }

    public func ClearSlot(slot: CName) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().ClearSlot(vehicle, slot);
            this.Say("Back to the style's own part.");
        }
    }

    public func ChooseCarPaint(paint: CName) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().ChooseCarPaint(vehicle, paint);
            this.Say(IsNameValid(paint) ? "Whole car in " + NameToString(paint) + ", on every panel that has it." : "Back to the finish's own paint.");
        }
    }

    public func ChoosePartPaint(slot: CName, paint: CName) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().ChoosePaint(vehicle, slot, paint);
            this.Say("Painted " + NameToString(paint) + ".");
        }
    }

    // The paint tool's Whole car brush.
    public func ChooseWholeCarPaint(paint: CName) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().ChooseWholeCarPaint(vehicle, paint);
            this.Say("Whole car painted.");
        }
    }

    // One corner of a part: the paint tool's click.
    public func ChooseCornerPaint(slot: CName, corner: CName, paint: CName) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().ChooseCornerPaint(vehicle, slot, corner, paint);
            this.Say("Painted.");
        }
    }

    // Drops a part's own paint; a part chosen only to carry that paint goes back to being the style's own.
    public func ClearPartPaint(slot: CName) {
        let vehicle = this.Changing();
        if !IsDefined(vehicle) {
            return;
        }
        let engine = this.Engine();
        let build = VCBuild.Parse(this.BuildText());
        let i = build.SlotIndex(slot);
        if i < 0 {
            return;
        }
        let cat = this.Catalog();
        let style = VCData.StyleOf(cat, this.CurrentLook());
        if Equals(NameToString(build.options[i]), NameToString(VCData.StyleOption(cat, style, slot))) {
            engine.ClearSlot(vehicle, slot);
        } else {
            engine.ChooseOption(vehicle, slot, build.options[i]);
        }
        this.Say("Paint as the finish has it.");
    }

    public func ChooseWheels(set: CName, label: String) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().ChooseWheels(vehicle, this.axle, set);
            this.Say(IsNameValid(set) ? "Trying " + label + "." : "The car's own wheels.");
        }
    }

    // A rim or a tire from the shared list on the chosen axle (this.axle), apart (2026-11-07); none for the car's own.
    public func ChooseRims(set: CName, label: String) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().ChooseRims(vehicle, this.axle, set);
            this.Say(IsNameValid(set) ? "Rims: " + label + "." : "The car's own rims.");
        }
    }

    public func ChooseTires(set: CName, label: String) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().ChooseTires(vehicle, this.axle, set);
            this.Say(IsNameValid(set) ? "Tires: " + label + "." : "The car's own tires.");
        }
    }

    // The wheels' size and width on the chosen axle, in percent of the car's own, set outright.
    public func SetFit(size: Float, width: Float) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().SetWheelFit(vehicle, this.axle, size, width);
            this.Say(s"Wheels at \(FloatToStringPrec(size, 0))% size, \(FloatToStringPrec(width, 0))% width.");
        }
    }

    // The rims' width on the chosen axle, in percent of the car's own wheels' width, set outright.
    public func SetRimWidth(width: Float) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().SetRimWidth(vehicle, this.axle, width);
            this.Say(s"Rims at \(FloatToStringPrec(width, 0))% width.");
        }
    }

    // The rims' width by a step.
    public func StepRimWidth(step: Float) {
        let vehicle = this.Changing();
        if !IsDefined(vehicle) {
            return;
        }
        let build = VCBuild.Parse(this.BuildText());
        let fit = Equals(this.axle, n"b") ? build.fitBack : build.fitFront;
        let w = ClampF((fit.Z <= 0.0 ? 100.0 : fit.Z) + step, 40.0, 250.0);
        this.Engine().SetRimWidth(vehicle, this.axle, w);
        this.Say(s"Rims at \(FloatToStringPrec(w, 0))% width.");
    }

    public func ChooseRimPaint(axle: CName, paint: CName) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().ChooseWheelPaint(vehicle, axle, paint);
            this.Say(IsNameValid(paint) ? "Rims in " + NameToString(paint) + "." : "Rims as they come.");
        }
    }

    // Size and width of the chosen axle's wheels, in percent of the car's own, by a step.
    public func StepFit(size: Float, width: Float) {
        let vehicle = this.Changing();
        if !IsDefined(vehicle) {
            return;
        }
        let build = VCBuild.Parse(this.BuildText());
        let fit = Equals(this.axle, n"b") ? build.fitBack : build.fitFront;
        let s = ClampF((fit.X <= 0.0 ? 100.0 : fit.X) + size, 50.0, 200.0);
        let w = ClampF((fit.Y <= 0.0 ? 100.0 : fit.Y) + width, 40.0, 250.0);
        this.Engine().SetWheelFit(vehicle, this.axle, s, w);
        this.Say(s"Wheels at \(FloatToStringPrec(s, 0))% size, \(FloatToStringPrec(w, 0))% width.");
    }

    public func ResetFit() {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().SetWheelFit(vehicle, this.axle, 100.0, 100.0);
            this.Say("Wheels at the car's own size.");
        }
    }

    public func ToggleKit(kit: CName, label: String) -> Bool {
        let vehicle = this.Changing();
        if !IsDefined(vehicle) {
            return false;
        }
        let on = this.Engine().ToggleKit(vehicle, kit);
        this.Say((on ? "Fitted " : "Took off ") + label + ".");
        return on;
    }

    public func NudgeKit(kit: CName, part: Int32, move: Vector4, turn: Vector4) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().NudgeKit(vehicle, kit, part, move, turn);
            this.Say("Moved.");
        }
    }

    public func ResetKitPlace(kit: CName, part: Int32) {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().ResetKitMoves(vehicle, kit, part);
            this.Say("Back where it came.");
        }
    }

    // --- service ---

    public func QuickFix() {
        let vehicle = this.Car();
        if !IsDefined(vehicle) {
            this.Say("No car here to fix.");
            return;
        }
        this.Engine().QuickFix(vehicle);
        this.Say("Dents out and glass in. Parts that came off stay off: a full refresh brings them back.");
    }

    // Sent away and called again: it comes back fresh, every lost part on, in its build.
    public func FullRefresh() {
        let vehicle = this.Car();
        if !IsDefined(vehicle) || this.Engine().PartnerLeads(vehicle) {
            this.Say("A partner is driving it, or it isn't out.");
            return;
        }
        this.SendAway(this.m_record);
        this.m_callAgain = this.m_record;
        this.Later(2, 1.0);
        this.Say("Sent away; it comes back fresh in a moment.");
    }

    public func BackToStock() {
        let vehicle = this.Changing();
        if IsDefined(vehicle) {
            this.Engine().ApplyBuildText(vehicle, "look=" + this.CurrentLook());
            this.Say("Back to the style's own parts and paint.");
        }
    }

    public func UndoVisit() {
        let i = ArrayFindFirst(this.m_startRecords, this.m_record);
        let vehicle = i >= 0 ? this.Changing() : null;
        if IsDefined(vehicle) {
            this.Engine().ApplyBuildText(vehicle, this.m_startTexts[i]);
            this.Say("The car as it was when you opened it.");
        }
    }

    public func Undo() {
        let vehicle = this.Car();
        if !IsDefined(vehicle) {
            return;
        }
        let i = ArraySize(this.m_undoRecords) - 1;
        while i >= 0 {
            if this.m_undoRecords[i] == this.m_record {
                let text = this.m_undoTexts[i];
                ArrayErase(this.m_undoRecords, i);
                ArrayErase(this.m_undoTexts, i);
                this.Engine().ApplyBuildText(vehicle, text);
                this.Say("Undone.");
                return;
            }
            i -= 1;
        }
        this.Say("Nothing to undo.");
    }

    public func Check() {
        let vehicle = this.Car();
        if IsDefined(vehicle) {
            this.Say("Check: " + this.Engine().Verify(vehicle));
        }
    }

    // --- the garage: buying, bringing, sending away ---
    // Buying saves the copy's build (that makes it the player's), puts it in V's garage and calls it, the game's way;
    // Bring here calls it and Send away sends it back the same way (user, 2026-11-07). From 2026-11-06 evening to
    // 2026-11-07 the screen spawned cars in front of V instead and shared them with NightCoop, after the game's call
    // brought nothing for a guest and buying a Barghest Apollo crashed; the crash turned out to be the screen's own
    // script (indexing a call's result), which most likely also gave the guest's call a garbage record. Whether a
    // guest's mid-session buy reaches their garage in the host's world is untried; if not, it goes to the host's
    // garage instead (user).

    // --- which copies are taken ---
    // A model has five copies: the game's one car per record, with four more (user, 2026-11-07). The same rules hold
    // as for a game car: two players who own the same copy have one car in a session, with one look, and both keep
    // its changes. Buying gets a copy this player doesn't own and, in a session, none a player there owns: each
    // player puts the copies they own in the session's state as one entry, "own.<their number>" (PublishOwned).
    // Which free copy is picked is random, so two players buying a model alone get the same copy one time in five,
    // not every time (the user and Bossun both got Cortes copy 1 that way on 2026-11-06). Fixed copies per player by
    // NightCoop name (2026-11-06 night) were dropped before they ever ran: they capped each player's copies and the
    // crew's size, for collisions the shared-car rule handles anyway.

    // The copy of a model this player gets, as an index into its pool: a random one of those neither they nor a
    // player here owns; -1 when there's none.
    public func FreeCopy(cat: CName) -> Int32 {
        let pool = VCData.Pool(cat);
        let free: array<Int32>;
        let i = 0;
        while i < ArraySize(pool) {
            if !this.IsOwned(pool[i]) && !this.TakenHere(pool[i]) {
                ArrayPush(free, i);
            }
            i += 1;
        }
        let count = ArraySize(free);
        if count == 0 {
            return -1;
        }
        let r = RandRange(0, count);
        if r < 0 || r >= count {
            r = count - 1;
        }
        return free[r];
    }

    // Whether a player in the session owns a copy (by the lists they put in).
    private func TakenHere(record: TweakDBID) -> Bool {
        let key = "," + VCEngine.SessionKey(record) + ",";
        for list in this.m_ownLists {
            if StrContains(list, key) {
                return true;
            }
        }
        return false;
    }

    // The name of the player here who owns a copy, or "" (none here, or a game car: their lists hold copies only).
    public func OwnerName(record: TweakDBID) -> String {
        let key = "," + VCEngine.SessionKey(record) + ",";
        let i = 0;
        while i < ArraySize(this.m_ownLists) {
            if StrContains(this.m_ownLists[i], key) {
                return this.Engine().PeerName(StringToInt(StrAfterFirst(this.m_ownKeys[i], ".")));
            }
            i += 1;
        }
        return "";
    }

    // A partner's list from the session's state ("" when it's gone): ",<key>,<key>,…,".
    public func OnOwnedList(key: String, list: String) {
        if Equals(key, VCOwnKey()) {
            return;
        }
        let i = ArrayFindFirst(this.m_ownKeys, key);
        if StrLen(list) == 0 {
            if i >= 0 {
                ArrayErase(this.m_ownKeys, i);
                ArrayErase(this.m_ownLists, i);
            }
        } else if i >= 0 {
            this.m_ownLists[i] = list;
        } else {
            ArrayPush(this.m_ownKeys, key);
            ArrayPush(this.m_ownLists, list);
        }
    }

    // Our list needs putting in: a session or a world started, or we bought or returned a copy.
    public func OwnedChanged() {
        this.m_ownDirty = true;
    }

    // The session ended: partners' lists are gone.
    public func ForgetOwned() {
        ArrayClear(this.m_ownKeys);
        ArrayClear(this.m_ownLists);
        this.m_ownDirty = true;
    }

    // NightCoop's frame, once a second in a session (Coop.reds): our list into the session's state when it needs it.
    public func PublishOwned() {
        if !this.m_ownDirty || !VCStateReady() {
            return;
        }
        let owned = this.Owned();
        let text = ",";
        for record in owned {
            text += VCEngine.SessionKey(record) + ",";
        }
        this.Engine().PutState(VCOwnKey(), text);
        this.m_ownDirty = false;
        this.Engine().Log(s"our \(ArraySize(owned)) shop car(s) listed in the session");
    }

    // A copy is this player's when it has a saved build (buying saves one). The garage isn't asked: the screen asked
    // the vehicle system about all 480 copies every second, and twice the game crashed in the vehicle system once a
    // copy was in V's garage (buying a Barghest Apollo; F7 beside a Quartz copy unlocked from the dev panel,
    // 2026-11-06 evening). It's called only when buying (the unlock) and returning (the lock).
    public func IsOwned(record: TweakDBID) -> Bool {
        return StrLen(this.Engine().GetBuildText(record)) > 0;
    }

    public func Buy(cat: CName, style: CName) {
        let n = this.FreeCopy(cat);
        if n < 0 {
            this.Say(VCShop.SoldOut());
            return;
        }
        // The pool into a local first: indexing a function's result straight away (VCData.Pool(cat)[n]) hands the
        // game the function's argument as if it were an address, and crashed the game buying an Outlaw and an Apollo
        // (Cyberpunk2077.exe+0x7bb8a0, the bad address the hash of the catalog's name; job "buy", 2026-11-06).
        let pool = VCData.Pool(cat);
        let record = pool[n];
        let base = VCData.Name(cat, "style." + NameToString(style) + ".base");
        let engine = this.Engine();
        // Saving the build makes the copy ours; in a session it goes in as the copy's build for everyone too, so a
        // partner's car is built right as it appears.
        engine.SetBuildText(record, "look=" + NameToString(base));
        engine.KeepBuild(record, "look=" + NameToString(base));
        let saved = engine.GetBuildText(record);
        // In V's garage, as designed (user, 2026-11-06). Buying crashed the game for a Barghest Apollo and a Herrera
        // Outlaw (Cyberpunk2077.exe+0x7bb8a0); the test job "buy" is finding which call does it.
        engine.Log(TDBID.ToStringDEBUG(record) + ": build saved, unlocking");
        let answer = engine.Unlock(record);
        engine.Log(TDBID.ToStringDEBUG(record) + s": unlock answered \(answer); selecting it");
        this.SetTarget(record);
        this.OwnedChanged();
        // The call's answer isn't what happened: it answered false for a Hella that came all the same (job "buy",
        // 2026-11-07), so it's only logged.
        let called = engine.Call(record);
        // Every step in the workshop log while buying is being tried out (2026-11-06).
        engine.Log("bought " + TDBID.ToStringDEBUG(record) + s": build saved \(StrLen(saved)) chars; unlock answered \(answer); call answered \(called)");
        this.Say("Bought. It's in your garage and on its way to you.");
    }

    public static func SoldOut() -> String {
        return "Sold out: all five of these belong to you or to players here.";
    }

    // Every pool copy this player has.
    public func Owned() -> array<TweakDBID> {
        let owned: array<TweakDBID>;
        for cat in VCData.Catalogs() {
            for record in VCData.Pool(cat) {
                if this.IsOwned(record) {
                    ArrayPush(owned, record);
                }
            }
        }
        return owned;
    }

    // Called from V's garage the game's way, as from its own vehicle menu (user, 2026-11-07); a partner driving it
    // keeps it.
    public func BringHere(record: TweakDBID) {
        this.SetTarget(record);
        let vehicle = this.Car();
        if IsDefined(vehicle) && this.Engine().PartnerLeads(vehicle) {
            this.Say("A partner is driving it.");
            return;
        }
        // The call's answer isn't what happened (see Buy).
        this.Engine().Call(record);
        this.Say("On its way to you.");
    }

    // Sent back to V's garage the game's way.
    public func SendAway(record: TweakDBID) {
        this.Engine().SendAway(record);
        this.Say("Put away.");
    }

    // Takes a copy back: put away, out of the garage and its build gone (the session's too), so it's free to buy again.
    public func ReturnCar(record: TweakDBID) {
        let engine = this.Engine();
        this.SendAway(record);
        engine.Lock(record);
        engine.SetBuildText(record, "");
        if engine.InSession() {
            engine.PutState(VCEngine.SessionKey(record), "");
        }
        this.OwnedChanged();
        if record == this.m_record {
            let none: TweakDBID;
            this.m_record = none;
        }
        this.garageCar = n"";
        this.Say("Returned to the shop.");
    }

    private func Later(what: Int32, seconds: Float) {
        let later = new VCShopLater();
        later.shop = this;
        later.what = what;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(later, seconds, false);
    }

    public func OnLater(what: Int32) {
        if what == 2 {
            // Full refresh: called again after being sent away.
            this.Engine().Call(this.m_callAgain);
        }
    }
    // --- views: V steps to a spot around the car, facing it ---

    public static func Rotate(v: Vector4, degrees: Float) -> Vector4 {
        let r = Deg2Rad(degrees);
        let c = CosF(r);
        let s = SinF(r);
        return new Vector4(v.X * c - v.Y * s, v.X * s + v.Y * c, 0.0, 0.0);
    }

    private func ViewDistance() -> Float {
        let cat = NameToString(this.Catalog());
        let d = 6.0;
        if Equals(NameToString(VCData.Name(this.Catalog(), "wheelKind")), "bike") {
            d = 3.5;
        } else if StrBeginsWith(cat, "kaukaz") || StrBeginsWith(cat, "mt28") || StrBeginsWith(cat, "militech_behemoth")
            || StrBeginsWith(cat, "chevalier_centurion") {
            d = 9.5;
        }
        return MaxF(2.5, d + this.viewExtra);
    }

    // angle: degrees from the car's front, to its left (90 is the left side, 180 the back).
    public func ViewFrom(angle: Float, label: String) {
        let game = this.GetGameInstance();
        let player = GetPlayer(game);
        let vehicle = this.Car();
        if !IsDefined(vehicle) || !IsDefined(player) {
            this.Say("No car to look at.");
            return;
        }
        if IsDefined(player.GetMountedVehicle()) {
            this.Say("Get out of the car to walk round it.");
            return;
        }
        let center = vehicle.GetWorldPosition();
        let direction = VCShop.Rotate(vehicle.GetWorldForward(), angle);
        let d = this.ViewDistance();
        let spot = new Vector4(center.X + direction.X * d, center.Y + direction.Y * d, center.Z + 0.2, 1.0);
        let found = GameInstance.GetNavigationSystem(game).FindPointInSphereOnlyHumanNavmesh(spot, 2.5, NavGenAgentSize.Human, false);
        if Equals(found.status, worldNavigationRequestStatus.OK) {
            spot = found.point;
        }
        // Facing the car, turned a little to the right so it sits in the part of the screen the panel leaves free.
        let look = new Vector4(center.X - spot.X, center.Y - spot.Y, 0.0, 0.0);
        GameInstance.GetTeleportationFacility(game).Teleport(player, spot, Vector4.ToRotation(VCShop.Rotate(look, -18.0)));
        this.Say("View: " + label + ".");
    }
}

public class VCShopLater extends DelayCallback {
    public let shop: wref<VCShop>;
    public let what: Int32;

    public func Call() {
        if IsDefined(this.shop) {
            this.shop.OnLater(this.what);
        }
    }
}
