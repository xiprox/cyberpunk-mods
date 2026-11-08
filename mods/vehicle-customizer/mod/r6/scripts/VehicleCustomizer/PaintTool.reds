// Vehicle Customizer: the paint tool (UX.md, "The paint tool and the tool rack"; RECORD.md, 2026-11-08). Load a colour, point and click.
// Empty, its screen is the menu: the top row is Factory and Swatches (Custom is left out for now, user), Down goes in. Swatches: Up
// and Down between groups, Left and Right along one. Factory: the aimed part's own paints, the list locked when you go in. Enter or
// a right click in a list loads. Loaded, it shows the colour and left click paints: the part under the crosshair, that corner alone,
// or the whole car (R changes the brush). Up empties it. On the top row or loaded, a right click copies the colour off the part or
// stand chip under the crosshair, so parts can be matched.
// The rules that stop it acting like a gun are ToolRules.reds, and what it can aim at on a car is the wrench's (VCTool.PartsAt).
module VehicleCustomizer

public abstract class VCPalette {
    public static func Groups() -> array<CName> {
        return TweakDBInterface.GetCNameArray(t"VehicleCustomizer.shop.groups");
    }

    private static func Key(group: CName, what: String) -> TweakDBID {
        return TDBID.Create("VehicleCustomizer.shop.group." + NameToString(group) + "." + what);
    }

    public static func Label(group: CName) -> String {
        return TweakDBInterface.GetString(VCPalette.Key(group, "label"), "");
    }

    public static func Paints(group: CName) -> array<CName> {
        return TweakDBInterface.GetCNameArray(VCPalette.Key(group, "paints"));
    }

    public static func Names(group: CName) -> array<String> {
        return TweakDBInterface.GetStringArray(VCPalette.Key(group, "names"));
    }

    public static func Colours(group: CName) -> array<Vector3> {
        return TweakDBInterface.GetVector3Array(VCPalette.Key(group, "colours"));
    }

    // Where a shop colour is in the palette; false if it isn't one.
    public static func Find(paint: CName, out group: Int32, out colour: Int32) -> Bool {
        let groups = VCPalette.Groups();
        let g = 0;
        while g < ArraySize(groups) {
            let paints = VCPalette.Paints(groups[g]);
            let c = 0;
            while c < ArraySize(paints) {
                if Equals(paints[c], paint) {
                    group = g;
                    colour = c;
                    return true;
                }
                c += 1;
            }
            g += 1;
        }
        return false;
    }
}

public class VCPaintTick extends DelayCallback {
    public let tool: wref<VCPaintTool>;

    public func Call() {
        if IsDefined(this.tool) {
            this.tool.Tick();
        }
    }
}

public class VCPaintTool extends ScriptableSystem {
    private let m_ticking: Bool;
    private let m_idle: Int32;
    private let m_held: Bool;

    // The tool's screens, each kept with its weapon; the panel goes on the one in V's own hands.
    private let m_screens: array<ref<VCToolScreen>>;
    private let m_lastScreenId: Int32;
    private let m_screenId: Int32;
    private let m_screenRoot: wref<inkCompoundWidget>;

    private let m_panel: wref<inkCanvas>;
    private let m_title: wref<inkText>;
    private let m_count: wref<inkText>;
    private let m_name: wref<inkText>;
    private let m_hint: wref<inkText>;
    private let m_chips: array<wref<inkRectangle>>;
    private let m_frame: wref<inkRectangle>;
    private let m_big: wref<inkRectangle>;

    // The menu: 0 the top row, 1 inside a list. m_source: 0 Factory, 1 Swatches.
    private let m_row: Int32;
    private let m_source: Int32;
    private let m_sourceSet: Bool;
    private let m_group: Int32;
    private let m_colour: Int32;
    private let m_factory: array<CName>; // locked when you go in
    private let m_factoryAt: Int32;
    private let m_factoryPart: String;

    // What's loaded: no paint means the tool is empty.
    private let m_loaded: CName;
    private let m_loadedName: String;
    private let m_loadedColour: Vector3;
    private let m_whole: Bool; // the brush: the part aimed at, or the whole car

    // What's under the crosshair: a part of a car, or a chip on the colour stand.
    private let m_car: wref<VehicleObject>;
    private let m_aim: ref<VCToolTab>;
    private let m_aimText: String;
    private let m_stand: wref<Entity>;
    private let m_chip: CName; // the chip's component
    private let m_chipPaint: CName;
    private let m_test: Bool;

    private let m_lit: CName;
    private let m_litWhole: Bool;
    private let m_litTarget: wref<Entity>;
    private let m_relightAt: Float;

    private let m_note: String;
    private let m_noteUntil: Float;

    public static func Get(game: GameInstance) -> ref<VCPaintTool> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(n"VehicleCustomizer.VCPaintTool") as VCPaintTool;
    }

    private func OnAttach() {
        GameInstance.GetCallbackSystem().RegisterCallback(n"Input/Key", this, n"OnKey");
    }

    private func OnDetach() {
        GameInstance.GetCallbackSystem().UnregisterCallback(n"Input/Key", this);
    }

    private func Now() -> Float {
        return EngineTime.ToFloat(GameInstance.GetSimTime(this.GetGameInstance()));
    }

    // --- the tool itself ---

    private func InInventory() -> ItemID {
        let player = GetPlayer(this.GetGameInstance());
        let items: array<wref<gameItemData>>;
        GameInstance.GetTransactionSystem(this.GetGameInstance()).GetItemList(player, items);
        for item in items {
            let id = item.GetID();
            if ItemID.GetTDBID(id) == t"Items.VC_PaintTool" {
                return id;
            }
        }
        let none: ItemID;
        return none;
    }

    public func Give() -> Bool {
        let game = this.GetGameInstance();
        let player = GetPlayer(game);
        if !IsDefined(player) {
            return false;
        }
        let id = this.InInventory();
        if !ItemID.IsValid(id) {
            GameInstance.GetTransactionSystem(game).GiveItemByTDBID(player, t"Items.VC_PaintTool", 1);
            id = this.InInventory();
        }
        if !ItemID.IsValid(id) {
            return false;
        }
        let draw = new RequestEquipHeavyWeapon();
        draw.itemID = id;
        player.QueueEvent(draw);
        this.StartTicking();
        return true;
    }

    public func IsHeld() -> Bool {
        let game = this.GetGameInstance();
        let player = GetPlayer(game);
        if !IsDefined(player) {
            return false;
        }
        let item = GameInstance.GetTransactionSystem(game).GetItemInSlot(player, t"AttachmentSlots.WeaponRight");
        return VCToolScreens.IsPaintTool(item as WeaponObject);
    }

    // --- ticking ---

    private func StartTicking() {
        this.m_idle = 0;
        if !this.m_ticking {
            this.m_ticking = true;
            this.Schedule();
        }
    }

    private func Schedule() {
        let tick = new VCPaintTick();
        tick.tool = this;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(tick, 0.1, false);
    }

    public func Tick() {
        if !this.IsHeld() {
            if this.m_held {
                this.m_held = false;
                this.Leave();
            }
            this.m_idle += 1;
            if this.m_idle < 50 {
                this.Schedule();
            } else {
                this.m_ticking = false;
            }
            return;
        }
        this.m_idle = 0;
        this.m_held = true;
        if !this.m_sourceSet {
            this.m_source = 1; // Swatches first: it needs no aim
            this.m_sourceSet = true;
        }
        this.AdoptScreen();
        this.Aim();
        this.Outline();
        this.Render();
        this.Schedule();
    }

    // Out of V's hands it goes back to the rack: empty, nothing outlined.
    private func Leave() {
        if IsDefined(this.m_panel) {
            this.m_panel.SetVisible(false);
        }
        this.Unlight();
        this.m_loaded = n"";
        this.m_row = 0;
        this.m_whole = false;
        this.m_car = null;
        this.m_aim = null;
        this.m_chip = n"";
        this.m_chipPaint = n"";
    }

    // --- the screen ---

    public func TakeScreen(root: ref<inkCompoundWidget>, weapon: wref<WeaponObject>) {
        let screen = new VCToolScreen();
        this.m_lastScreenId += 1;
        screen.id = this.m_lastScreenId;
        screen.weapon = weapon;
        screen.root = root;
        ArrayPush(this.m_screens, screen);
        this.StartTicking();
    }

    private func AdoptScreen() {
        let game = this.GetGameInstance();
        let held = GameInstance.GetTransactionSystem(game).GetItemInSlot(GetPlayer(game), t"AttachmentSlots.WeaponRight") as WeaponObject;
        let found: ref<VCToolScreen>;
        let i = ArraySize(this.m_screens) - 1;
        while i >= 0 {
            let screen = this.m_screens[i];
            if !IsDefined(screen.weapon) || !IsDefined(screen.root) {
                ArrayErase(this.m_screens, i);
            } else if !IsDefined(found) && IsDefined(held) && screen.weapon.GetEntityID() == held.GetEntityID() {
                found = screen;
            }
            i -= 1;
        }
        if !IsDefined(found) || found.id == this.m_screenId {
            return;
        }
        this.m_screenId = found.id;
        this.m_screenRoot = found.root;
        if IsDefined(this.m_panel) {
            let parent = this.m_panel.GetParentWidget() as inkCompoundWidget;
            if IsDefined(parent) {
                parent.RemoveChild(this.m_panel);
            }
            this.m_panel = null;
        }
    }

    public func HasScreen() -> Bool {
        return IsDefined(this.m_screenRoot);
    }

    private static func Cyan() -> HDRColor {
        return new HDRColor(0.369, 0.965, 1.0, 1.0);
    }

    private static func MakeText(parent: ref<inkCompoundWidget>, name: CName, size: Int32, style: CName, x: Float, y: Float) -> ref<inkText> {
        let text = new inkText();
        text.SetName(name);
        text.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        text.SetFontStyle(style);
        text.SetFontSize(size);
        text.SetLetterCase(textLetterCase.UpperCase);
        text.SetTintColor(VCPaintTool.Cyan());
        text.SetAnchor(inkEAnchor.TopLeft);
        text.SetMargin(new inkMargin(x, y, 0.0, 0.0));
        text.Reparent(parent);
        return text;
    }

    private static func MakeRect(parent: ref<inkCompoundWidget>, name: CName, x: Float, y: Float, w: Float, h: Float) -> ref<inkRectangle> {
        let rect = new inkRectangle();
        rect.SetName(name);
        rect.SetAnchor(inkEAnchor.TopLeft);
        rect.SetMargin(new inkMargin(x, y, 0.0, 0.0));
        rect.SetSize(w, h);
        rect.Reparent(parent);
        return rect;
    }

    private static func Width() -> Float {
        return 440.0;
    }

    private static func Height() -> Float {
        return 172.0;
    }

    private static func ChipCount() -> Int32 {
        return 7;
    }

    // On the tool's own screen if it has one; the HUD only until it does (as the wrench's panel).
    private func EnsurePanel() -> Bool {
        if IsDefined(this.m_panel) {
            return true;
        }
        let onScreen = IsDefined(this.m_screenRoot);
        let root: wref<inkCompoundWidget> = onScreen ? this.m_screenRoot : GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer").GetVirtualWindow();
        if !IsDefined(root) {
            return false;
        }
        let panel = new inkCanvas();
        panel.SetName(n"vc_paint_panel");
        panel.SetAnchor(inkEAnchor.Centered);
        panel.SetAnchorPoint(new Vector2(0.0, 0.0));
        panel.SetSize(VCPaintTool.Width(), VCPaintTool.Height());
        panel.SetTranslation(new Vector2(120.0, 36.0));
        if onScreen {
            let size = root.GetSize();
            let scale = MinF(size.X / VCPaintTool.Width(), size.Y / VCPaintTool.Height());
            panel.SetAnchorPoint(new Vector2(0.5, 0.5));
            panel.SetTranslation(new Vector2(0.0, 0.0));
            panel.SetScale(new Vector2(scale, scale));
        }
        panel.Reparent(root);
        this.m_title = VCPaintTool.MakeText(panel, n"title", 17, n"Medium", 22.0, 8.0);
        let count = VCPaintTool.MakeText(panel, n"count", 17, n"Medium", 0.0, 0.0);
        count.SetAnchor(inkEAnchor.TopRight);
        count.SetAnchorPoint(new Vector2(1.0, 0.0));
        count.SetMargin(new inkMargin(0.0, 8.0, 14.0, 0.0));
        this.m_count = count;
        // Everything in the panel's top 125: below that the tool's screen is off the bottom of the view (test run, 2026-11-08).
        let frame = VCPaintTool.MakeRect(panel, n"frame", 0.0, 26.0, 56.0, 46.0);
        frame.SetTintColor(VCPaintTool.Cyan());
        this.m_frame = frame;
        ArrayClear(this.m_chips);
        let i = 0;
        while i < VCPaintTool.ChipCount() {
            ArrayPush(this.m_chips, VCPaintTool.MakeRect(panel, StringToName("chip" + ToString(i)), 22.0 + 57.0 * Cast<Float>(i), 32.0, 44.0, 34.0));
            i += 1;
        }
        this.m_big = VCPaintTool.MakeRect(panel, n"big", 22.0, 30.0, 396.0, 38.0);
        this.m_name = VCPaintTool.MakeText(panel, n"name", 27, n"Semi-Bold", 22.0, 72.0);
        this.m_hint = VCPaintTool.MakeText(panel, n"hint", 15, n"Medium", 22.0, 106.0);
        this.m_panel = panel;
        return true;
    }

    private static func Tint(c: Vector3) -> HDRColor {
        return new HDRColor(c.X, c.Y, c.Z, 1.0);
    }

    private static func Pretty(paint: CName) -> String {
        return StrReplaceAll(NameToString(paint), "_", " ");
    }

    private func HideChips() {
        for chip in this.m_chips {
            chip.SetVisible(false);
        }
    }

    private func RenderLoaded() -> String {
        this.m_big.SetVisible(true);
        this.m_frame.SetVisible(false);
        this.HideChips();
        this.m_big.SetTintColor(VCPaintTool.Tint(this.m_loadedColour));
        this.m_title.SetText(this.m_whole ? "Whole car" : this.m_aimText);
        this.m_count.SetText(this.m_whole ? "Whole car" : "Part");
        this.m_name.SetText(this.m_loadedName);
        return "Left click paints   R brush   Up empties";
    }

    private func RenderTop() -> String {
        this.m_big.SetVisible(false);
        this.m_frame.SetVisible(false);
        this.HideChips();
        this.m_title.SetText(this.m_aimText);
        this.m_count.SetText("");
        this.m_name.SetText(this.m_source == 0 ? "[Factory]   Swatches" : "Factory   [Swatches]");
        return "Down goes in   Right click copies";
    }

    private func RenderSwatches() -> String {
        this.m_big.SetVisible(false);
        this.HideChips();
        let groups = VCPalette.Groups();
        if ArraySize(groups) == 0 {
            this.m_frame.SetVisible(false);
            return "";
        }
        let group = groups[this.m_group];
        let colours = VCPalette.Colours(group);
        let names = VCPalette.Names(group);
        let n = ArraySize(colours);
        let shown = VCPaintTool.ChipCount();
        let first = Max(0, Min(this.m_colour - shown / 2, n - shown));
        let k = 0;
        while k < shown && first + k < n {
            let chip = this.m_chips[k];
            chip.SetVisible(true);
            chip.SetTintColor(VCPaintTool.Tint(colours[first + k]));
            k += 1;
        }
        this.m_frame.SetVisible(true);
        this.m_frame.SetMargin(new inkMargin(22.0 + 57.0 * Cast<Float>(this.m_colour - first) - 6.0, 26.0, 0.0, 0.0));
        this.m_title.SetText(VCPalette.Label(group));
        this.m_count.SetText(s"\(this.m_colour + 1) / \(n)");
        this.m_name.SetText(this.m_colour < ArraySize(names) ? names[this.m_colour] : "");
        return "Arrows choose   Enter loads";
    }

    private func RenderFactory() -> String {
        this.m_big.SetVisible(false);
        this.m_frame.SetVisible(false);
        this.HideChips();
        let n = ArraySize(this.m_factory);
        this.m_title.SetText("Factory: " + this.m_factoryPart);
        this.m_count.SetText(s"\(this.m_factoryAt + 1) / \(n)");
        this.m_name.SetText(n > 0 ? "<  " + VCPaintTool.Pretty(this.m_factory[this.m_factoryAt]) + "  >" : "");
        return "Left / Right choose   Enter loads   Up back";
    }

    private func Render() {
        if !this.m_held || !this.EnsurePanel() {
            if IsDefined(this.m_panel) {
                this.m_panel.SetVisible(false);
            }
            return;
        }
        this.m_panel.SetVisible(true);
        let keys: String;
        if IsNameValid(this.m_loaded) {
            keys = this.RenderLoaded();
        } else if this.m_row == 0 {
            keys = this.RenderTop();
        } else if this.m_source == 1 {
            keys = this.RenderSwatches();
        } else {
            keys = this.RenderFactory();
        }
        let showingNote = StrLen(this.m_note) > 0 && this.Now() < this.m_noteUntil;
        this.m_hint.SetText(showingNote ? this.m_note : keys);
        this.m_hint.SetTintColor(showingNote ? new HDRColor(1.0, 0.85, 0.45, 1.0) : VCPaintTool.Cyan());
    }

    private func Say(text: String) {
        this.m_note = text;
        this.m_noteUntil = this.Now() + 3.0;
    }

    // --- aiming ---

    // The chip under the crosshair on a colour stand: the nearest to the ray, within a chip's half width (the stand's chips are
    // components named vc_chip_<colour>; palette-stand/). The stand is found by its tag.
    private func AimAtStand() -> Bool {
        let game = this.GetGameInstance();
        let origin: Vector4;
        let dir: Vector4;
        if !VCTool.Get(game).AimRay(origin, dir) {
            return false;
        }
        let stands = GameInstance.GetDynamicEntitySystem().GetTagged(n"vc_stand");
        let best = 0.05;
        let found = false;
        for stand in stands {
            let parts = stand.GetComponents();
            for component in parts {
                let mesh = component as MeshComponent;
                let name = IsDefined(mesh) ? NameToString(mesh.name) : "";
                if StrBeginsWith(name, "vc_chip_") {
                    let p = Matrix.GetTranslation(mesh.GetLocalToWorld());
                    let vx = p.X - origin.X;
                    let vy = p.Y - origin.Y;
                    let vz = p.Z - origin.Z;
                    let t = vx * dir.X + vy * dir.Y + vz * dir.Z;
                    if t > 0.2 && t < 7.0 {
                        let ax = vx - dir.X * t;
                        let ay = vy - dir.Y * t;
                        let az = vz - dir.Z * t;
                        let off = SqrtF(ax * ax + ay * ay + az * az);
                        if off < best {
                            best = off;
                            found = true;
                            this.m_stand = stand;
                            this.m_chip = mesh.name;
                            this.m_chipPaint = StringToName("vcs_" + StrRight(name, StrLen(name) - 8));
                        }
                    }
                }
            }
        }
        return found;
    }

    private func Aim() {
        if this.m_test {
            return;
        }
        let game = this.GetGameInstance();
        let engine = VCEngine.Get(game);
        let player = GetPlayer(game);
        if !IsDefined(engine) || !IsDefined(player) {
            return;
        }
        this.m_chip = n"";
        this.m_chipPaint = n"";
        if this.AimAtStand() {
            this.m_car = null;
            this.m_aim = null;
            this.m_aimText = VCPaintTool.Pretty(this.m_chipPaint);
            let group: Int32;
            let colour: Int32;
            if VCPalette.Find(this.m_chipPaint, group, colour) {
                let groups = VCPalette.Groups();
                let names = VCPalette.Names(groups[group]);
                this.m_aimText = names[colour];
            }
            return;
        }
        let looked = GameInstance.GetTargetingSystem(game).GetLookAtObject(player, false, false) as VehicleObject;
        if !IsDefined(looked) || !engine.IsOurs(looked.GetRecordID()) {
            this.m_car = null;
            this.m_aim = null;
            this.m_aimText = IsDefined(looked) ? "Not a car of ours" : "Aim at a car";
            return;
        }
        this.m_car = looked;
        let parts = VCTool.Get(game).PartsAt(looked);
        if ArraySize(parts) > 0 {
            this.m_aim = parts[0];
            this.m_aimText = this.m_aim.label;
        } else {
            this.m_aim = null;
            this.m_aimText = "Aim at a part";
        }
    }

    // Tests: a part to take as aimed at, in place of the crosshair.
    public func TestAim(car: ref<VehicleObject>, slot: CName, corner: CName, part: CName, on: Bool) {
        this.m_test = on;
        if on {
            let tab = new VCToolTab();
            tab.slot = slot;
            tab.corner = corner;
            tab.part = part;
            tab.label = NameToString(part);
            this.m_car = car;
            this.m_aim = tab;
            this.m_aimText = tab.label;
        }
    }

    private func Light(target: ref<Entity>, part: CName, whole: Bool, on: Bool) {
        if !IsDefined(target) {
            return;
        }
        let evt = new entRenderHighlightEvent();
        if !whole {
            evt.componentName = part;
        }
        evt.seeThroughWalls = false;
        evt.outlineIndex = on ? (whole ? Cast<Uint8>(3u) : Cast<Uint8>(1u)) : Cast<Uint8>(0u);
        evt.fillIndex = Cast<Uint8>(0u);
        evt.opacity = on ? 1.0 : 0.0;
        target.QueueEvent(evt);
    }

    private func Unlight() {
        if IsDefined(this.m_litTarget) && (this.m_litWhole || IsNameValid(this.m_lit)) {
            this.Light(this.m_litTarget, this.m_lit, this.m_litWhole, false);
        }
        this.m_lit = n"";
        this.m_litWhole = false;
        this.m_litTarget = null;
    }

    private func Outline() {
        let target: wref<Entity>;
        let want = n"";
        let whole = false;
        if IsNameValid(this.m_chip) {
            target = this.m_stand;
            want = this.m_chip;
        } else if IsDefined(this.m_car) {
            target = this.m_car;
            if this.m_whole && IsNameValid(this.m_loaded) {
                whole = true;
            } else if IsDefined(this.m_aim) {
                want = this.m_aim.part;
            }
        }
        let same = IsDefined(target) && IsDefined(this.m_litTarget) && this.m_litTarget.GetEntityID() == target.GetEntityID()
            && Equals(want, this.m_lit) && Equals(whole, this.m_litWhole);
        if same && this.Now() < this.m_relightAt {
            return;
        }
        this.Unlight();
        if IsDefined(target) && (whole || IsNameValid(want)) {
            this.Light(target, want, whole, true);
            this.m_lit = want;
            this.m_litWhole = whole;
            this.m_litTarget = target;
        }
        // Sent again every 2 s: a rebuild makes the parts anew and drops the outline.
        this.m_relightAt = this.Now() + 2.0;
    }

    // --- keys ---

    private cb func OnKey(event: ref<KeyInputEvent>) {
        if !Equals(event.GetAction(), EInputAction.IACT_Press) || !this.m_held {
            return;
        }
        let game = this.GetGameInstance();
        let shop = VCShop.Get(game);
        if IsDefined(shop) && shop.IsOpen() {
            return;
        }
        let ui = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UI_System);
        if IsDefined(ui) && ui.GetBool(GetAllBlackboardDefs().UI_System.IsInMenu) {
            return;
        }
        switch event.GetKey() {
            case EInputKey.IK_Left: this.Press(n"left"); break;
            case EInputKey.IK_Right: this.Press(n"right"); break;
            case EInputKey.IK_Up: this.Press(n"up"); break;
            case EInputKey.IK_Down: this.Press(n"down"); break;
            case EInputKey.IK_Enter: this.Press(n"enter"); break;
            case EInputKey.IK_R: this.Press(n"brush"); break;
            case EInputKey.IK_LeftMouse: this.Press(n"paint"); break;
            case EInputKey.IK_RightMouse: this.Press(n"copy"); break;
        }
    }

    private static func Wrap(i: Int32, n: Int32) -> Int32 {
        if n <= 0 {
            return 0;
        }
        return ((i % n) + n) % n;
    }

    // A paint in the tool: a shop colour with its name and chip, or a factory paint, which only has its name.
    private func LoadPaint(paint: CName) {
        let group: Int32;
        let colour: Int32;
        this.m_loaded = paint;
        if VCPalette.Find(paint, group, colour) {
            let groups = VCPalette.Groups();
            let g = groups[group];
            let names = VCPalette.Names(g);
            let colours = VCPalette.Colours(g);
            this.m_loadedName = names[colour];
            this.m_loadedColour = colours[colour];
            this.m_group = group;
            this.m_colour = colour;
        } else {
            this.m_loadedName = VCPaintTool.Pretty(paint);
            this.m_loadedColour = new Vector3(0.35, 0.38, 0.40);
        }
    }

    private func LoadSelection() {
        if this.m_source == 1 {
            let groups = VCPalette.Groups();
            if ArraySize(groups) > 0 {
                let paints = VCPalette.Paints(groups[this.m_group]);
                if this.m_colour < ArraySize(paints) {
                    this.LoadPaint(paints[this.m_colour]);
                }
            }
        } else if this.m_factoryAt < ArraySize(this.m_factory) {
            this.LoadPaint(this.m_factory[this.m_factoryAt]);
        }
    }

    // Down from the top row: Swatches always opens; Factory takes the aimed part's own paints and keeps them, wherever you look next.
    private func GoIn() {
        if this.m_source == 1 {
            this.m_row = 1;
            return;
        }
        if !IsDefined(this.m_car) || !IsDefined(this.m_aim) || !IsNameValid(this.m_aim.slot) {
            this.Say("Aim at a part first");
            return;
        }
        let cat = VCEngine.Get(this.GetGameInstance()).CatalogOf(this.m_car.GetRecordID());
        let option = this.OptionOn(this.m_car, cat, this.m_aim.slot);
        let paints = VCData.Names(cat, "option." + NameToString(option) + ".paints");
        if ArraySize(paints) == 0 {
            this.Say("No factory paints on this part");
            return;
        }
        this.m_factory = paints;
        this.m_factoryAt = 0;
        this.m_factoryPart = this.m_aim.label;
        this.m_row = 1;
    }

    // The right click: the colour off what's under the crosshair.
    private func Copy() {
        if IsNameValid(this.m_chipPaint) {
            this.LoadPaint(this.m_chipPaint);
            this.Say("Copied " + this.m_loadedName);
            return;
        }
        if !IsDefined(this.m_car) || !IsDefined(this.m_aim) {
            this.Say("Aim at a part to copy it");
            return;
        }
        let part = this.m_car.FindComponentByName(this.m_aim.part) as MeshComponent;
        if !IsDefined(part) {
            this.Say("Nothing to copy there");
            return;
        }
        this.LoadPaint(part.meshAppearance);
        this.Say("Copied " + this.m_loadedName);
    }

    // One key's worth of the tool (public for tests).
    public func Press(key: CName) {
        if IsNameValid(this.m_loaded) {
            if Equals(key, n"up") {
                this.m_loaded = n"";
            } else if Equals(key, n"paint") {
                this.Click();
            } else if Equals(key, n"copy") {
                this.Copy();
            } else if Equals(key, n"brush") {
                this.m_whole = !this.m_whole;
                this.m_relightAt = 0.0;
            }
        } else if this.m_row == 0 {
            if Equals(key, n"left") || Equals(key, n"right") {
                this.m_source = this.m_source == 0 ? 1 : 0;
            } else if Equals(key, n"down") || Equals(key, n"enter") {
                this.GoIn();
            } else if Equals(key, n"copy") {
                this.Copy();
            } else if Equals(key, n"paint") {
                this.Say("Load a colour first");
            }
        } else if this.m_source == 1 {
            let groups = VCPalette.Groups();
            if Equals(key, n"up") {
                if this.m_group == 0 {
                    this.m_row = 0;
                } else {
                    this.m_group -= 1;
                    this.m_colour = 0;
                }
            } else if Equals(key, n"down") {
                if this.m_group + 1 < ArraySize(groups) {
                    this.m_group += 1;
                    this.m_colour = 0;
                }
            } else if (Equals(key, n"left") || Equals(key, n"right")) && ArraySize(groups) > 0 {
                let paints = VCPalette.Paints(groups[this.m_group]);
                this.m_colour = VCPaintTool.Wrap(this.m_colour + (Equals(key, n"left") ? -1 : 1), ArraySize(paints));
            } else if Equals(key, n"enter") || Equals(key, n"copy") {
                this.LoadSelection();
            } else if Equals(key, n"paint") {
                this.Say("Load a colour first");
            }
        } else {
            if Equals(key, n"up") {
                this.m_row = 0;
            } else if Equals(key, n"left") || Equals(key, n"right") {
                this.m_factoryAt = VCPaintTool.Wrap(this.m_factoryAt + (Equals(key, n"left") ? -1 : 1), ArraySize(this.m_factory));
            } else if Equals(key, n"enter") || Equals(key, n"copy") {
                this.LoadSelection();
            } else if Equals(key, n"paint") {
                this.Say("Load a colour first");
            }
        }
        this.Render();
    }

    // For tests.
    public func Selected() -> String {
        let groups = VCPalette.Groups();
        if ArraySize(groups) == 0 {
            return "";
        }
        let paints = VCPalette.Paints(groups[this.m_group]);
        return this.m_colour < ArraySize(paints) ? NameToString(paints[this.m_colour]) : "";
    }

    public func Loaded() -> String {
        return IsNameValid(this.m_loaded) ? NameToString(this.m_loaded) : "";
    }

    public func Row() -> Int32 {
        return this.m_row;
    }

    public func Brush() -> String {
        return this.m_whole ? "whole" : "part";
    }

    public func FactoryCount() -> Int32 {
        return ArraySize(this.m_factory);
    }

    public func Note() -> String {
        return this.m_note;
    }

    // --- painting ---

    private func OptionOn(car: ref<VehicleObject>, cat: CName, slot: CName) -> CName {
        let build = VCBuild.Parse(VCEngine.Get(this.GetGameInstance()).BuildTextOf(car));
        let i = build.SlotIndex(slot);
        let option = i >= 0 ? build.options[i] : n"";
        if !IsNameValid(option) {
            let look = IsNameValid(build.look) ? NameToString(build.look) : VCData.BaseLook(NameToString(car.GetCurrentAppearanceName()));
            option = VCData.StyleOption(cat, VCData.StyleOf(cat, look), slot);
        }
        return option;
    }

    private func Click() {
        if IsNameValid(this.m_chip) {
            this.Say("Right click copies from the stand");
            return;
        }
        if !IsDefined(this.m_car) {
            this.Say(this.m_aimText);
            return;
        }
        if this.m_whole {
            let shop = VCShop.Get(this.GetGameInstance());
            shop.SetTarget(this.m_car.GetRecordID());
            shop.ChooseWholeCarPaint(this.m_loaded);
            this.Say(shop.Message());
            this.m_relightAt = this.Now() + 1.2;
            return;
        }
        if !IsDefined(this.m_aim) || !IsNameValid(this.m_aim.slot) {
            this.Say("Can't paint this part alone: R for the whole car");
            return;
        }
        this.PaintPart(this.m_car, this.m_aim.slot, this.m_aim.corner);
    }

    // The loaded colour on one corner of a slot's part, if that part has it (public for tests).
    public func PaintPart(car: ref<VehicleObject>, slot: CName, corner: CName) -> Bool {
        let game = this.GetGameInstance();
        let engine = VCEngine.Get(game);
        let cat = engine.CatalogOf(car.GetRecordID());
        let option = this.OptionOn(car, cat, slot);
        let offered = VCData.Names(cat, "option." + NameToString(option) + ".paints");
        if !IsNameValid(option) || !VCData.Offers(cat, option, offered, this.m_loaded) {
            this.Say(StrBeginsWith(NameToString(this.m_loaded), "vcs_") ? "No colours on this part" : "This part doesn't have that paint");
            return false;
        }
        let shop = VCShop.Get(game);
        shop.SetTarget(car.GetRecordID());
        shop.ChooseCornerPaint(slot, corner, this.m_loaded);
        this.Say(shop.Message());
        this.m_relightAt = this.Now() + 1.2;
        return true;
    }
}
