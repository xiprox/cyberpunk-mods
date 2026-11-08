// Vehicle Customizer: the tool (UX.md, "a tool in your hand"; RECORD.md, 2026-11-07).
// Held like a turret's gun (the heavy slot: a weapon switch drops it, anyone can pick it up), it never fires. Aimed at
// one of our cars, the part under the crosshair is outlined green and the tool's screen shows a grid: the top row its
// tabs (the car, then each part under the crosshair), Down goes into a row, Left and Right choose, Up goes back
// (user's design). A choice goes on once it has rested half a second, so scrolling past options rebuilds nothing;
// Enter puts it on at once, Backspace undoes. Every change goes through the shop (Shop.reds), so undo, saving and
// co-op work as on the F7 screen. The F7 screen's Service tab hands the tool over.
// For now the tool is a stand-in, a copy of the Kyubi (tool.yaml); our own model with a bigger screen comes next.
// The part under the crosshair: each part's box (boxes.yaml, by its mesh's hash) carried into the world by its
// component's transform and tested against the crosshair's ray; the nearest part wins, unless a smaller one starts
// within 40 cm of it (a rim inside its tire's box); shells as big as the body come last (probes, 2026-11-07).
module VehicleCustomizer

public class VCToolTab {
    public let slot: CName; // n"" for the car itself and for an add-on's part
    public let corner: CName;
    public let kit: CName; // a fitted add-on's part (vc_kit_<kit>_<n>)
    public let part: CName; // the component outlined
    public let label: String;

    public func IsCar() -> Bool {
        return !IsNameValid(this.slot) && !IsNameValid(this.kit);
    }
}

public class VCToolTick extends DelayCallback {
    public let tool: wref<VCTool>;

    public func Call() {
        if IsDefined(this.tool) {
            this.tool.Tick();
        }
    }
}

public class VCTool extends ScriptableSystem {
    // The screen: its lines, on every screen the tool has.
    private let m_lines: array<wref<inkText>>;
    private let m_lineCount: Int32;
    private let m_ticking: Bool;
    private let m_idle: Int32;
    private let m_held: Bool;

    private let m_car: wref<VehicleObject>;
    private let m_tabs: array<ref<VCToolTab>>;
    private let m_aimed: CName;
    private let m_hint: String;
    private let m_row: Int32; // 0 the tabs, 1 what to change, 2 the choices
    private let m_tab: Int32;
    private let m_kinds: array<CName>;
    private let m_kind: Int32;
    private let m_choiceIds: array<CName>;
    private let m_choiceLabels: array<String>;
    private let m_choiceValues: array<Float>; // a size's or width's percent, with its id
    private let m_choice: Int32;
    // Which wheels a rim or tire change goes on: n"all" all of them, else the aimed part's axle. Back to the aimed
    // axle whenever the tab changes, so a tab named "Back rims" changes the back rims unless you chose otherwise on
    // it (user, 2026-11-07).
    private let m_wheelScope: CName;
    private let m_pending: Bool;
    private let m_pendingAt: Float;
    private let m_note: String;
    private let m_noteUntil: Float;

    // The HUD panel.
    private let m_hud: wref<inkCanvas>;
    private let m_hudHeader: wref<inkText>;
    private let m_hudTabs: wref<inkHorizontalPanel>;
    private let m_hudKinds: wref<inkHorizontalPanel>;
    private let m_hudChoice: wref<inkText>;
    private let m_hudCount: wref<inkText>;
    private let m_hudBar: wref<inkRectangle>;
    private let m_hudHint: wref<inkText>;
    private let m_hudMarker: wref<inkRectangle>;
    private let m_hudTabsKey: String;
    private let m_hudKindsKey: String;

    // What's outlined, and when to send it again (a rebuild makes the car's parts anew).
    private let m_lit: CName;
    private let m_litWhole: Bool;
    private let m_litCar: wref<VehicleObject>;
    private let m_relightAt: Float;

    // Tests (dev's "toolui" job): a ray to aim along instead of the camera's.
    private let m_testRay: Bool;
    private let m_testOrigin: Vector4;
    private let m_testDir: Vector4;

    public static func Get(game: GameInstance) -> ref<VCTool> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(n"VehicleCustomizer.VCTool") as VCTool;
    }

    public static func IsTool(weapon: ref<WeaponObject>) -> Bool {
        return IsDefined(weapon) && ItemID.GetTDBID(weapon.GetItemID()) == t"Items.VC_Tool";
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

    private func ToolInInventory() -> ItemID {
        let player = GetPlayer(this.GetGameInstance());
        let items: array<wref<gameItemData>>;
        GameInstance.GetTransactionSystem(this.GetGameInstance()).GetItemList(player, items);
        for item in items {
            let id = item.GetID();
            if ItemID.GetTDBID(id) == t"Items.VC_Tool" {
                return id;
            }
        }
        let none: ItemID;
        return none;
    }

    // Puts the tool in V's hands (one, from the inventory if V has it, else a new one).
    public func Give() -> Bool {
        let game = this.GetGameInstance();
        let player = GetPlayer(game);
        if !IsDefined(player) {
            return false;
        }
        let id = this.ToolInInventory();
        if !ItemID.IsValid(id) {
            GameInstance.GetTransactionSystem(game).GiveItemByTDBID(player, t"Items.VC_Tool", 1);
            id = this.ToolInInventory();
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
        return VCTool.IsTool(item as WeaponObject);
    }

    // --- the screen ---

    // Called by the screen's controller as the tool is drawn: its own content hidden, a backing and our lines added.
    public func BuildScreen(root: ref<inkCompoundWidget>) {
        if !IsDefined(root) {
            return;
        }
        let i = 0;
        while i < root.GetNumChildren() {
            root.GetWidget(i).SetVisible(false);
            i += 1;
        }
        let size = root.GetSize();
        let w = size.X > 10.0 ? size.X : 500.0;
        let h = size.Y > 10.0 ? size.Y : 500.0;
        let back = new inkRectangle();
        back.SetName(n"vc_tool_back");
        back.SetSize(w, h);
        back.SetTintColor(new HDRColor(0.02, 0.04, 0.05, 1.0));
        back.SetOpacity(0.92);
        back.Reparent(root);
        let rows = 4;
        let r = 0;
        while r < rows {
            let text = new inkText();
            text.SetName(StringToName("vc_tool_line_" + ToString(r)));
            text.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
            text.SetFontStyle(n"Semi-Bold");
            text.SetFontSize(r == 2 ? 64 : 52);
            text.SetLetterCase(textLetterCase.UpperCase);
            text.SetHorizontalAlignment(textHorizontalAlignment.Center);
            text.SetVerticalAlignment(textVerticalAlignment.Center);
            text.SetSize(w - 20.0, h / Cast<Float>(rows));
            text.SetMargin(new inkMargin(10.0, h / Cast<Float>(rows) * Cast<Float>(r), 0.0, 0.0));
            text.Reparent(root);
            ArrayPush(this.m_lines, text);
            r += 1;
        }
        this.m_lineCount = rows;
        this.StartTicking();
        this.Render();
    }

    public func HasScreen() -> Bool {
        for line in this.m_lines {
            if IsDefined(line) {
                return true;
            }
        }
        return false;
    }

    // What the screen shows now, one line per row, for tests.
    public func ScreenText() -> String {
        let out = "";
        let i = 0;
        while i < ArraySize(this.m_lines) && i < this.m_lineCount {
            if IsDefined(this.m_lines[i]) {
                out += (i > 0 ? " / " : "") + this.m_lines[i].GetText();
            }
            i += 1;
        }
        return out;
    }

    private func SetLine(r: Int32, text: String, bright: Bool) {
        let i = 0;
        while i < ArraySize(this.m_lines) {
            if i % this.m_lineCount == r && IsDefined(this.m_lines[i]) {
                this.m_lines[i].SetText(text);
                this.m_lines[i].SetTintColor(bright ? new HDRColor(0.45, 1.0, 0.65, 1.0) : new HDRColor(0.30, 0.55, 0.45, 1.0));
            }
            i += 1;
        }
    }

    // --- ticking: aiming, the pending choice, the outline, the screen ---

    private func StartTicking() {
        this.m_idle = 0;
        if !this.m_ticking {
            this.m_ticking = true;
            this.Schedule();
        }
    }

    private func Schedule() {
        let tick = new VCToolTick();
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
        if this.m_row == 0 {
            this.Aim();
        }
        if this.m_pending && this.Now() >= this.m_pendingAt {
            this.m_pending = false;
            this.Apply();
        }
        this.Outline();
        this.Render();
        this.Schedule();
    }

    // The tool left V's hands: nothing outlined, back to the top row.
    private func Leave() {
        this.HideHud();
        this.Unlight();
        this.m_row = 0;
        this.m_pending = false;
        this.m_car = null;
        ArrayClear(this.m_tabs);
        this.m_aimed = n"";
        this.m_wheelScope = n"";
    }

    // --- aiming ---

    public func TestAim(car: ref<VehicleObject>, origin: Vector4, dir: Vector4, on: Bool) {
        this.m_testRay = on;
        this.m_testOrigin = origin;
        this.m_testDir = dir;
        if on {
            this.m_car = car;
            this.m_row = 0;
            this.m_aimed = n"";
        }
    }

    public func Row() -> Int32 {
        return this.m_row;
    }

    private func Ray(out origin: Vector4, out dir: Vector4) -> Bool {
        if this.m_testRay {
            origin = this.m_testOrigin;
            dir = Vector4.Normalize(this.m_testDir);
            return true;
        }
        let player = GetPlayer(this.GetGameInstance()) as PlayerPuppet;
        if !IsDefined(player) {
            return false;
        }
        let camera = player.GetFPPCameraComponent();
        if !IsDefined(camera) {
            return false;
        }
        let m = camera.GetLocalToWorld();
        origin = Matrix.GetTranslation(m);
        dir = Vector4.Normalize(Matrix.GetAxisY(m));
        return true;
    }

    // The car under the crosshair, ours or none, and its parts under it as tabs.
    private func Aim() {
        let game = this.GetGameInstance();
        let engine = VCEngine.Get(game);
        let player = GetPlayer(game);
        if !IsDefined(engine) || !IsDefined(player) {
            return;
        }
        let looked = GameInstance.GetTargetingSystem(game).GetLookAtObject(player, false, false) as VehicleObject;
        if this.m_testRay && !IsDefined(looked) {
            looked = this.m_car;
        }
        if !IsDefined(looked) || !engine.IsOurs(looked.GetRecordID()) {
            this.m_hint = IsDefined(looked) ? "Not a car of ours" : "Aim at a car";
            if IsDefined(this.m_car) {
                this.m_car = null;
                ArrayClear(this.m_tabs);
                this.m_aimed = n"";
                this.m_tab = 0;
            }
            return;
        }
        this.m_hint = "";
        let changed = !IsDefined(this.m_car) || !(this.m_car.GetEntityID() == looked.GetEntityID());
        this.m_car = looked;
        let parts = this.PartsUnderCrosshair(looked);
        let first = ArraySize(parts) > 0 ? parts[0].part : n"";
        if changed || !Equals(first, this.m_aimed) || ArraySize(this.m_tabs) == 0 {
            ArrayClear(this.m_tabs);
            let car = new VCToolTab();
            car.label = "Whole car";
            ArrayPush(this.m_tabs, car);
            for part in parts {
                ArrayPush(this.m_tabs, part);
            }
            this.m_tab = ArraySize(parts) > 0 ? 1 : 0;
            this.m_aimed = first;
            this.m_wheelScope = n"";
        }
    }

    // A part's slot and corner, from the look's list (slot|corner|part) or our own parts' names (vc_slot_<slot>_<corner>).
    private func SlotOf(rows: array<CName>, name: String, out slot: CName, out corner: CName) -> Bool {
        if StrBeginsWith(name, "vc_slot_") {
            let rest = StrRight(name, StrLen(name) - 8);
            let cut = StrFindLast(rest, "_");
            if cut > 0 {
                slot = StringToName(StrLeft(rest, cut));
                corner = StringToName(StrRight(rest, StrLen(rest) - cut - 1));
                return true;
            }
            return false;
        }
        for row in rows {
            let text = NameToString(row);
            let a = StrFindFirst(text, "|");
            let b = StrFindLast(text, "|");
            if a > 0 && b > a && Equals(StrRight(text, StrLen(text) - b - 1), name) {
                slot = StringToName(StrLeft(text, a));
                corner = StringToName(StrMid(text, a + 1, b - a - 1));
                return true;
            }
        }
        return false;
    }

    private static func BoxKey(part: ref<MeshComponent>) -> String {
        let mesh = part.mesh;
        let hash = ResourceAsyncRef.GetHash(mesh);
        let signed = Cast<Int64>(hash);
        return signed < 0l ? "n" + s"\(-signed)" : "p" + s"\(signed)";
    }

    // Where the ray first enters the box (min, max in the part's own space) through the part's world matrix; -1 if it
    // misses. size is the box's volume in the world.
    private static func RayBox(origin: Vector4, dir: Vector4, m: Matrix, mn: Vector3, mx: Vector3, out size: Float) -> Float {
        let X = Matrix.GetAxisX(m);
        let Y = Matrix.GetAxisY(m);
        let Z = Matrix.GetAxisZ(m);
        let W = Matrix.GetTranslation(m);
        let a = X.X; let b = Y.X; let c = Z.X;
        let d = X.Y; let e = Y.Y; let f = Z.Y;
        let g = X.Z; let h = Y.Z; let i = Z.Z;
        let A = e * i - f * h;
        let B = -(d * i - f * g);
        let C = d * h - e * g;
        let det = a * A + b * B + c * C;
        if AbsF(det) < 0.000001 {
            return -1.0;
        }
        let D = -(b * i - c * h);
        let E = a * i - c * g;
        let F = -(a * h - b * g);
        let G = b * f - c * e;
        let H = -(a * f - c * d);
        let I = a * e - b * d;
        let px = origin.X - W.X;
        let py = origin.Y - W.Y;
        let pz = origin.Z - W.Z;
        let o: array<Float> = [(A * px + D * py + G * pz) / det, (B * px + E * py + H * pz) / det, (C * px + F * py + I * pz) / det];
        let v: array<Float> = [(A * dir.X + D * dir.Y + G * dir.Z) / det, (B * dir.X + E * dir.Y + H * dir.Z) / det,
            (C * dir.X + F * dir.Y + I * dir.Z) / det];
        let lo: array<Float> = [mn.X, mn.Y, mn.Z];
        let hi: array<Float> = [mx.X, mx.Y, mx.Z];
        let tmin = -100000.0;
        let tmax = 100000.0;
        let k = 0;
        while k < 3 {
            if AbsF(v[k]) < 0.000001 {
                if o[k] < lo[k] || o[k] > hi[k] {
                    return -1.0;
                }
            } else {
                let t1 = (lo[k] - o[k]) / v[k];
                let t2 = (hi[k] - o[k]) / v[k];
                if t1 > t2 {
                    let t = t1;
                    t1 = t2;
                    t2 = t;
                }
                tmin = MaxF(tmin, t1);
                tmax = MinF(tmax, t2);
                if tmin > tmax {
                    return -1.0;
                }
            }
            k += 1;
        }
        if tmax < 0.0 {
            return -1.0;
        }
        size = (hi[0] - lo[0]) * (hi[1] - lo[1]) * (hi[2] - lo[2]) * AbsF(det);
        return MaxF(tmin, 0.0);
    }

    // The car's parts that can change under the crosshair, as tabs, the one to light first.
    private func PartsUnderCrosshair(car: ref<VehicleObject>) -> array<ref<VCToolTab>> {
        let found: array<ref<VCToolTab>>;
        let origin: Vector4;
        let dir: Vector4;
        if !this.Ray(origin, dir) {
            return found;
        }
        let engine = VCEngine.Get(this.GetGameInstance());
        let cat = engine.CatalogOf(car.GetRecordID());
        let look = VCData.BaseLook(NameToString(car.GetCurrentAppearanceName()));
        let rows = VCData.Names(cat, "look." + look + ".parts");
        let tabs: array<ref<VCToolTab>>;
        let ts: array<Float>;
        let sizes: array<Float>;
        for component in car.GetComponents() {
            let part = component as MeshComponent;
            let name = IsDefined(part) ? NameToString(part.name) : "";
            let slot: CName;
            let corner: CName;
            // A fitted add-on's part: vc_kit_<kit>_<n> (Engine.reds), its kit the name between.
            let kit = n"";
            if StrBeginsWith(name, "vc_kit_") {
                let rest = StrRight(name, StrLen(name) - 7);
                let cut = StrFindLast(rest, "_");
                if cut > 0 {
                    kit = StringToName(StrLeft(rest, cut));
                }
            }
            if IsDefined(part) && part.IsEnabled() && !StrEndsWith(name, "_shadow")
                && (IsNameValid(kit) || this.SlotOf(rows, name, slot, corner)) {
                let box = TweakDBInterface.GetVector3Array(TDBID.Create("VehicleCustomizer.box." + VCTool.BoxKey(part)));
                if ArraySize(box) >= 2 {
                    let size = 0.0;
                    let t = VCTool.RayBox(origin, dir, part.GetLocalToWorld(), box[0], box[1], size);
                    if t >= 0.0 {
                        let tab = new VCToolTab();
                        tab.slot = slot;
                        tab.corner = corner;
                        tab.kit = kit;
                        tab.part = part.name;
                        if IsNameValid(kit) {
                            tab.label = "Add-on: " + VCTool.Pretty(VCData.Text(cat, "kit." + NameToString(kit) + ".code"));
                        } else if VCEngine.IsWheelSlot(cat, slot) {
                            // Rims and tires go by axle: "Front rims", a bike's "Back tire".
                            let bike = StrLen(NameToString(corner)) == 1;
                            let tire = VCTool.IsTireSlot(slot);
                            tab.label = (VCTool.Front(corner) ? "Front " : "Back ")
                                + (tire ? (bike ? "tire" : "tires") : (bike ? "rim" : "rims"));
                        } else {
                            tab.label = VCData.Text(cat, "slot." + NameToString(slot) + ".label");
                        }
                        if StrLen(tab.label) == 0 {
                            tab.label = name;
                        }
                        ArrayPush(tabs, tab);
                        ArrayPush(ts, t);
                        ArrayPush(sizes, size);
                    }
                }
            }
        }
        // The first: the nearest part, unless a smaller one starts within 40 cm of it; shells over 3 m3 only alone.
        let nearest = -1;
        let shell = -1;
        let n = 0;
        while n < ArraySize(tabs) {
            if sizes[n] > 3.0 {
                if shell < 0 || ts[n] < ts[shell] {
                    shell = n;
                }
            } else if nearest < 0 || ts[n] < ts[nearest] {
                nearest = n;
            }
            n += 1;
        }
        let best = nearest;
        if best >= 0 {
            n = 0;
            while n < ArraySize(tabs) {
                if sizes[n] <= 3.0 && ts[n] <= ts[nearest] + 0.4 && sizes[n] < sizes[best] {
                    best = n;
                }
                n += 1;
            }
        } else {
            best = shell;
        }
        // Then the rest by distance, one tab per slot and corner, four at most.
        let used: array<Bool>;
        n = 0;
        while n < ArraySize(tabs) {
            ArrayPush(used, false);
            n += 1;
        }
        if best >= 0 {
            ArrayPush(found, tabs[best]);
            used[best] = true;
        }
        while ArraySize(found) < 4 {
            let next = -1;
            n = 0;
            while n < ArraySize(tabs) {
                if !used[n] && (next < 0 || ts[n] < ts[next]) {
                    next = n;
                }
                n += 1;
            }
            if next < 0 {
                break;
            }
            used[next] = true;
            // One tab per slot and corner; a rim or tire one per axle, as they're chosen by axle.
            let same = false;
            let wheel = VCEngine.IsWheelSlot(cat, tabs[next].slot);
            for have in found {
                if Equals(have.slot, tabs[next].slot) && Equals(have.kit, tabs[next].kit) && (Equals(have.corner, tabs[next].corner)
                    || wheel && Equals(VCTool.Front(have.corner), VCTool.Front(tabs[next].corner))) {
                    same = true;
                }
            }
            if !same {
                ArrayPush(found, tabs[next]);
            }
        }
        return found;
    }

    // --- the outline ---

    private func Light(car: ref<VehicleObject>, part: CName, whole: Bool, on: Bool) {
        if !IsDefined(car) {
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
        car.QueueEvent(evt);
    }

    private func Unlight() {
        if IsDefined(this.m_litCar) && (this.m_litWhole || IsNameValid(this.m_lit)) {
            this.Light(this.m_litCar, this.m_lit, this.m_litWhole, false);
        }
        this.m_lit = n"";
        this.m_litWhole = false;
        this.m_litCar = null;
    }

    private func Outline() {
        let car = this.m_car;
        let want = n"";
        let whole = false;
        if IsDefined(car) && this.m_tab >= 0 && this.m_tab < ArraySize(this.m_tabs) {
            let tab = this.m_tabs[this.m_tab];
            if tab.IsCar() {
                whole = true;
            } else {
                want = tab.part;
            }
        }
        let same = IsDefined(car) && IsDefined(this.m_litCar) && this.m_litCar.GetEntityID() == car.GetEntityID()
            && Equals(want, this.m_lit) && Equals(whole, this.m_litWhole);
        if same && this.Now() < this.m_relightAt {
            return;
        }
        this.Unlight();
        if IsDefined(car) && (whole || IsNameValid(want)) {
            this.Light(car, want, whole, true);
            this.m_lit = want;
            this.m_litWhole = whole;
            this.m_litCar = car;
        }
        // Sent again every 2 s: a rebuild makes the parts anew and drops the outline.
        this.m_relightAt = this.Now() + 2.0;
    }

    // --- rows and choices ---

    private func Catalog() -> CName {
        return IsDefined(this.m_car) ? VCEngine.Get(this.GetGameInstance()).CatalogOf(this.m_car.GetRecordID()) : n"";
    }

    private func Build() -> ref<VCBuild> {
        if !IsDefined(this.m_car) {
            return new VCBuild();
        }
        return VCBuild.Parse(VCEngine.Get(this.GetGameInstance()).BuildTextOf(this.m_car));
    }

    private func CurrentTab() -> ref<VCToolTab> {
        return this.m_tab >= 0 && this.m_tab < ArraySize(this.m_tabs) ? this.m_tabs[this.m_tab] : null;
    }

    private func OptionInEffect(cat: CName, build: ref<VCBuild>, slot: CName) -> CName {
        let i = build.SlotIndex(slot);
        if i >= 0 {
            return build.options[i];
        }
        let look = IsNameValid(build.look) ? NameToString(build.look) : VCData.BaseLook(NameToString(this.m_car.GetCurrentAppearanceName()));
        return VCData.StyleOption(cat, VCData.StyleOf(cat, look), slot);
    }

    // The whole car's paints: the body's, else the first part's that has paints (as the F7 screen does).
    private func CarPaints(cat: CName, build: ref<VCBuild>) -> array<CName> {
        let body = this.OptionInEffect(cat, build, n"base.body");
        if IsNameValid(body) {
            return VCData.Names(cat, "option." + NameToString(body) + ".paints");
        }
        for slot in VCData.Names(cat, "slots") {
            let paints = VCData.Names(cat, "option." + NameToString(this.OptionInEffect(cat, build, slot)) + ".paints");
            if ArraySize(paints) > 0 {
                return paints;
            }
        }
        let none: array<CName>;
        return none;
    }

    private func MakeKinds() {
        ArrayClear(this.m_kinds);
        let tab = this.CurrentTab();
        let cat = this.Catalog();
        if !IsDefined(tab) || !IsNameValid(cat) {
            return;
        }
        let build = this.Build();
        // Every list in a local before ArraySize: a call's result passed straight to it reads garbage (the first tool
        // run's part tabs all said "nothing to change"; root CLAUDE.md, "Redscript calls' results").
        if IsNameValid(tab.kit) {
            ArrayPush(this.m_kinds, n"takeoff");
            return;
        }
        // The whole car: only what spans the car (UX.md, "Where options live"); rims and tires are on their parts.
        if tab.IsCar() {
            ArrayPush(this.m_kinds, n"style");
            let carPaints = this.CarPaints(cat, build);
            if ArraySize(carPaints) > 0 {
                ArrayPush(this.m_kinds, n"paint");
            }
            let kits = VCData.Names(cat, "kits");
            if ArraySize(kits) > 0 {
                ArrayPush(this.m_kinds, n"addons");
            }
            return;
        }
        // A rim: every rim (this car's own first), its paint, its width, and which wheels. A tire: every tire, the
        // wheel's size, the tire's width, and which wheels. Each width is its part's alone, to match one to the other.
        if VCEngine.IsWheelSlot(cat, tab.slot) {
            if VCTool.IsTireSlot(tab.slot) {
                ArrayPush(this.m_kinds, n"tire");
                ArrayPush(this.m_kinds, n"size");
                ArrayPush(this.m_kinds, n"width");
            } else {
                ArrayPush(this.m_kinds, n"rim");
                let rimPaints = this.RimPaints(cat, build, tab);
                if ArraySize(rimPaints) > 0 {
                    ArrayPush(this.m_kinds, n"rimpaint");
                }
                ArrayPush(this.m_kinds, n"rimwidth");
            }
            ArrayPush(this.m_kinds, n"axles");
            return;
        }
        let options = VCData.Names(cat, "slot." + NameToString(tab.slot) + ".options");
        if ArraySize(options) > 0 {
            ArrayPush(this.m_kinds, n"part");
        }
        let option = this.OptionInEffect(cat, build, tab.slot);
        let paints = VCData.Names(cat, "option." + NameToString(option) + ".paints");
        if IsNameValid(option) && ArraySize(paints) > 0 {
            ArrayPush(this.m_kinds, n"partpaint");
        }
    }

    private static func KindLabel(kind: CName) -> String {
        switch kind {
            case n"style": return "Style";
            case n"paint": return "Paint";
            case n"part": return "Part";
            case n"partpaint": return "Paint";
            case n"addons": return "Add-ons";
            case n"takeoff": return "Take it off";
            case n"rim": return "Rim";
            case n"rimpaint": return "Paint";
            case n"tire": return "Tire";
            case n"size": return "Size";
            case n"width": return "Width";
            case n"rimwidth": return "Width";
        }
        return NameToString(kind);
    }

    // A kind's name in the row; which wheels a change goes on says what's chosen ("Back wheels", "All wheels").
    private func KindText(kind: CName) -> String {
        if Equals(kind, n"axles") {
            let tab = this.CurrentTab();
            let bike = this.IsBike();
            if Equals(this.m_wheelScope, n"all") || !IsDefined(tab) {
                return bike ? "Both wheels" : "All wheels";
            }
            return VCTool.Front(tab.corner) ? (bike ? "Front wheel" : "Front wheels") : (bike ? "Back wheel" : "Back wheels");
        }
        return VCTool.KindLabel(kind);
    }

    // --- rims and tires ---

    public static func IsTireSlot(slot: CName) -> Bool {
        return StrEndsWith(NameToString(slot), ".tire");
    }

    // A corner's axle: fl, fr, f are the front.
    public static func Front(corner: CName) -> Bool {
        return StrBeginsWith(NameToString(corner), "f");
    }

    private func IsBike() -> Bool {
        return Equals(VCData.Name(this.Catalog(), "wheelKind"), n"bike");
    }

    // The axle a wheel change goes on, for the shop: the aimed part's, unless all of them were chosen on this tab
    // (user, 2026-11-07: a "Back rims" tab changing all four by default was unexpected).
    private func Axle(tab: ref<VCToolTab>) -> CName {
        if Equals(this.m_wheelScope, n"all") {
            return n"all";
        }
        return VCTool.Front(tab.corner) ? n"f" : n"b";
    }

    // The paints of the rim on the aimed axle: a chosen rim's, else the car's own rim's.
    private func RimPaints(cat: CName, build: ref<VCBuild>, tab: ref<VCToolTab>) -> array<CName> {
        let set = VCTool.Front(tab.corner) ? build.rimFront : build.rimBack;
        if IsNameValid(set) {
            let paints = TweakDBInterface.GetCNameArray(VCData.WheelKey(set, "paints"));
            return paints;
        }
        let option = this.OptionInEffect(cat, build, tab.slot);
        let own = VCData.Names(cat, "option." + NameToString(option) + ".paints");
        return own;
    }

    // The aimed axle's wheel size, tire width or rim width (n"size", n"width", n"rimwidth"), in percent of the car's
    // own.
    private static func FitValue(build: ref<VCBuild>, front: Bool, kind: CName) -> Float {
        let fit = front ? build.fitFront : build.fitBack;
        let value = Equals(kind, n"size") ? fit.X : (Equals(kind, n"width") ? fit.Y : fit.Z);
        return value <= 0.0 ? 100.0 : value;
    }

    private static func IsFitKind(kind: CName) -> Bool {
        return Equals(kind, n"size") || Equals(kind, n"width") || Equals(kind, n"rimwidth");
    }

    private static func FitId(value: Float) -> CName {
        return StringToName(FloatToStringPrec(value, 0));
    }

    // What's on the car now for a kind of choice, as the id its choice has.
    private func NowOf(kind: CName, tab: ref<VCToolTab>, cat: CName, build: ref<VCBuild>) -> CName {
        let front = VCTool.Front(tab.corner);
        if Equals(kind, n"style") {
            let look = IsNameValid(build.look) ? NameToString(build.look) : VCData.BaseLook(NameToString(this.m_car.GetCurrentAppearanceName()));
            return VCData.StyleOf(cat, look);
        }
        if Equals(kind, n"paint") {
            return build.paint;
        }
        if Equals(kind, n"part") {
            let i = build.SlotIndex(tab.slot);
            return i >= 0 ? build.options[i] : n"";
        }
        if Equals(kind, n"partpaint") {
            let i = build.SlotIndex(tab.slot);
            return i >= 0 ? build.paints[i] : n"";
        }
        if Equals(kind, n"rim") {
            return front ? build.rimFront : build.rimBack;
        }
        if Equals(kind, n"tire") {
            return front ? build.tireFront : build.tireBack;
        }
        if Equals(kind, n"rimpaint") {
            return front ? build.wheelPaintFront : build.wheelPaintBack;
        }
        if VCTool.IsFitKind(kind) {
            return VCTool.FitId(VCTool.FitValue(build, front, kind));
        }
        if Equals(kind, n"axles") {
            return Equals(this.m_wheelScope, n"all") ? n"all" : n"one";
        }
        return n"";
    }

    // The choices for the row below, and which one is on the car now.
    private func MakeChoices() {
        ArrayClear(this.m_choiceIds);
        ArrayClear(this.m_choiceLabels);
        ArrayClear(this.m_choiceValues);
        this.m_choice = 0;
        let tab = this.CurrentTab();
        let cat = this.Catalog();
        if !IsDefined(tab) || this.m_kind < 0 || this.m_kind >= ArraySize(this.m_kinds) {
            return;
        }
        let build = this.Build();
        let kind = this.m_kinds[this.m_kind];
        let front = VCTool.Front(tab.corner);
        if Equals(kind, n"style") {
            for style in VCData.Names(cat, "styles") {
                ArrayPush(this.m_choiceIds, style);
                ArrayPush(this.m_choiceLabels, VCData.Text(cat, "style." + NameToString(style) + ".label"));
            }
        } else if Equals(kind, n"paint") {
            ArrayPush(this.m_choiceIds, n"");
            ArrayPush(this.m_choiceLabels, "The finish's own");
            for paint in this.CarPaints(cat, build) {
                ArrayPush(this.m_choiceIds, paint);
                ArrayPush(this.m_choiceLabels, NameToString(paint));
            }
        } else if Equals(kind, n"part") {
            ArrayPush(this.m_choiceIds, n"");
            ArrayPush(this.m_choiceLabels, "Style's own");
            for option in VCData.Names(cat, "slot." + NameToString(tab.slot) + ".options") {
                ArrayPush(this.m_choiceIds, option);
                ArrayPush(this.m_choiceLabels, VCData.Text(cat, "option." + NameToString(option) + ".code"));
            }
        } else if Equals(kind, n"partpaint") {
            ArrayPush(this.m_choiceIds, n"");
            ArrayPush(this.m_choiceLabels, "As it comes");
            let option = this.OptionInEffect(cat, build, tab.slot);
            for paint in VCData.Names(cat, "option." + NameToString(option) + ".paints") {
                ArrayPush(this.m_choiceIds, paint);
                ArrayPush(this.m_choiceLabels, NameToString(paint));
            }
        } else if Equals(kind, n"rim") || Equals(kind, n"tire") {
            // The car's own, this car's other own ones, then every other vehicle's (Wheels.reds), each scaled to fit.
            let tire = Equals(kind, n"tire");
            for set in VCWheels.List(cat, tire) {
                ArrayPush(this.m_choiceIds, set);
                ArrayPush(this.m_choiceLabels, VCWheels.Label(set, tire));
            }
        } else if Equals(kind, n"rimpaint") {
            ArrayPush(this.m_choiceIds, n"");
            ArrayPush(this.m_choiceLabels, "As it comes");
            for paint in this.RimPaints(cat, build, tab) {
                ArrayPush(this.m_choiceIds, paint);
                ArrayPush(this.m_choiceLabels, NameToString(paint));
            }
        } else if VCTool.IsFitKind(kind) {
            // In steps of 5 over the range the F7 screen allows, with the wheels' own value among them if it was set
            // in finer steps there.
            let size = Equals(kind, n"size");
            let current = VCTool.FitValue(build, front, kind);
            let lo = size ? 50.0 : 40.0;
            let hi = size ? 200.0 : 250.0;
            let values: array<Float>;
            let placed = false;
            let v = lo;
            while v <= hi + 0.01 {
                if !placed && current < v - 0.5 {
                    ArrayPush(values, current);
                    placed = true;
                }
                if AbsF(current - v) < 0.5 {
                    placed = true;
                }
                ArrayPush(values, v);
                v += 5.0;
            }
            if !placed {
                ArrayPush(values, current);
            }
            for value in values {
                ArrayPush(this.m_choiceIds, VCTool.FitId(value));
                ArrayPush(this.m_choiceValues, value);
                ArrayPush(this.m_choiceLabels, FloatToStringPrec(value, 0) + "%"
                    + (AbsF(value - 100.0) < 0.5 ? (size ? " (own size)" : " (auto)") : ""));
            }
        } else if Equals(kind, n"axles") {
            // The aimed axle first: it's what the tab says and what a change goes on unless all are chosen.
            let bike = this.IsBike();
            ArrayPush(this.m_choiceIds, n"one");
            ArrayPush(this.m_choiceLabels, front ? (bike ? "Front wheel only" : "Front wheels only") : (bike ? "Back wheel only" : "Back wheels only"));
            ArrayPush(this.m_choiceIds, n"all");
            ArrayPush(this.m_choiceLabels, bike ? "Both wheels" : "All wheels");
        } else if Equals(kind, n"addons") {
            // Every kit of the car; Enter puts one on or takes it off (not on resting: scrolling past ten sticker
            // sets mustn't put them on and off).
            for kit in VCData.Names(cat, "kits") {
                ArrayPush(this.m_choiceIds, kit);
                ArrayPush(this.m_choiceLabels, VCData.Text(cat, "kit." + NameToString(kit) + ".code"));
            }
        }
        let now = this.NowOf(kind, tab, cat, build);
        let k = ArrayFindFirst(this.m_choiceIds, now);
        this.m_choice = k >= 0 ? k : 0;
    }

    // Puts the chosen one on the car, through the shop.
    private func Apply() {
        let tab = this.CurrentTab();
        if !IsDefined(this.m_car) || !IsDefined(tab) || this.m_choice < 0 || this.m_choice >= ArraySize(this.m_choiceIds)
            || this.m_kind < 0 || this.m_kind >= ArraySize(this.m_kinds) {
            return;
        }
        let id = this.m_choiceIds[this.m_choice];
        let label = this.m_choiceLabels[this.m_choice];
        let kind = this.m_kinds[this.m_kind];
        if Equals(kind, n"axles") {
            // Not a change to the car: which wheels the next ones go on.
            this.m_wheelScope = id;
            this.Say("Changes here now go on " + StrLower(label));
            return;
        }
        let shop = VCShop.Get(this.GetGameInstance());
        let cat = this.Catalog();
        let build = this.Build();
        let front = VCTool.Front(tab.corner);
        shop.SetTarget(this.m_car.GetRecordID());
        // The shop's axle is the F7 screen's too: set for this change, then put back.
        let keepAxle = shop.axle;
        shop.axle = this.Axle(tab);
        if Equals(kind, n"style") {
            if !Equals(this.NowOf(kind, tab, cat, build), id) {
                shop.ChooseLook(VCData.Name(cat, "style." + NameToString(id) + ".base"), label);
            }
        } else if Equals(kind, n"paint") {
            shop.ChooseCarPaint(id);
        } else if Equals(kind, n"part") {
            if IsNameValid(id) {
                shop.ChooseOption(tab.slot, id, label);
            } else {
                shop.ClearSlot(tab.slot);
            }
        } else if Equals(kind, n"partpaint") {
            if IsNameValid(id) {
                shop.ChoosePartPaint(tab.slot, id);
            } else {
                shop.ClearPartPaint(tab.slot);
            }
        } else if Equals(kind, n"rim") {
            shop.ChooseRims(id, label);
        } else if Equals(kind, n"tire") {
            shop.ChooseTires(id, label);
        } else if Equals(kind, n"rimpaint") {
            shop.ChooseRimPaint(shop.axle, id);
        } else if Equals(kind, n"size") && this.m_choice < ArraySize(this.m_choiceValues) {
            shop.SetFit(this.m_choiceValues[this.m_choice], VCTool.FitValue(build, front, n"width"));
        } else if Equals(kind, n"width") && this.m_choice < ArraySize(this.m_choiceValues) {
            shop.SetFit(VCTool.FitValue(build, front, n"size"), this.m_choiceValues[this.m_choice]);
        } else if Equals(kind, n"rimwidth") && this.m_choice < ArraySize(this.m_choiceValues) {
            shop.SetRimWidth(this.m_choiceValues[this.m_choice]);
        }
        shop.axle = keepAxle;
        this.Say(shop.Message());
        this.m_relightAt = this.Now() + 1.2;
    }

    private func CurrentKind() -> CName {
        return this.m_kind >= 0 && this.m_kind < ArraySize(this.m_kinds) ? this.m_kinds[this.m_kind] : n"";
    }

    // An add-on on or off, through the shop (which keeps it for undo and says what it did).
    private func ToggleKit(kit: CName, label: String) {
        if !IsDefined(this.m_car) || !IsNameValid(kit) {
            return;
        }
        let shop = VCShop.Get(this.GetGameInstance());
        shop.SetTarget(this.m_car.GetRecordID());
        shop.ToggleKit(kit, VCTool.Pretty(label));
        this.Say(shop.Message());
        this.m_relightAt = this.Now() + 1.2;
    }

    private func KitOn(kit: CName) -> Bool {
        let build = this.Build();
        return build.KitIndex(kit) >= 0;
    }

    // --- keys ---

    private cb func OnKey(event: ref<KeyInputEvent>) {
        if !Equals(event.GetAction(), EInputAction.IACT_Press) || !this.m_held {
            return;
        }
        let shop = VCShop.Get(this.GetGameInstance());
        if IsDefined(shop) && shop.IsOpen() {
            return;
        }
        switch event.GetKey() {
            case EInputKey.IK_Left: this.Press(n"left"); break;
            case EInputKey.IK_Right: this.Press(n"right"); break;
            case EInputKey.IK_Up: this.Press(n"up"); break;
            case EInputKey.IK_Down: this.Press(n"down"); break;
            case EInputKey.IK_Enter: this.Press(n"enter"); break;
            case EInputKey.IK_Backspace: this.Press(n"back"); break;
        }
    }

    private static func Wrap(i: Int32, n: Int32) -> Int32 {
        if n <= 0 {
            return 0;
        }
        return ((i % n) + n) % n;
    }

    // One key's worth of moving through the grid (public for tests).
    public func Press(key: CName) {
        if Equals(key, n"back") {
            this.m_pending = false;
            let shop = VCShop.Get(this.GetGameInstance());
            shop.Undo();
            this.Say(shop.Message());
            if this.m_row == 2 {
                let keep = this.m_kind;
                this.MakeChoices();
                this.m_kind = keep;
            }
            this.m_relightAt = this.Now() + 1.2;
        } else if this.m_row == 0 {
            if Equals(key, n"left") || Equals(key, n"right") {
                this.m_tab = VCTool.Wrap(this.m_tab + (Equals(key, n"left") ? -1 : 1), ArraySize(this.m_tabs));
                this.m_wheelScope = n"";
            } else if Equals(key, n"down") || Equals(key, n"enter") {
                if IsDefined(this.m_car) && ArraySize(this.m_tabs) > 0 {
                    this.MakeKinds();
                    if ArraySize(this.m_kinds) > 0 {
                        this.m_row = 1;
                        this.m_kind = 0;
                        this.m_note = "";
                    } else {
                        this.Say("Nothing to change on this part");
                    }
                }
            }
        } else if this.m_row == 1 {
            if Equals(key, n"left") || Equals(key, n"right") {
                this.m_kind = VCTool.Wrap(this.m_kind + (Equals(key, n"left") ? -1 : 1), ArraySize(this.m_kinds));
            } else if Equals(key, n"down") || Equals(key, n"enter") {
                if Equals(this.CurrentKind(), n"takeoff") {
                    // An add-on's part: off with its whole kit, then back to aiming.
                    let tab = this.CurrentTab();
                    this.ToggleKit(tab.kit, tab.label);
                    this.m_row = 0;
                    this.m_aimed = n"";
                } else {
                    this.MakeChoices();
                    if ArraySize(this.m_choiceIds) > 0 {
                        this.m_row = 2;
                    }
                }
            } else if Equals(key, n"up") {
                this.m_row = 0;
            }
        } else {
            let addons = Equals(this.CurrentKind(), n"addons");
            if Equals(key, n"left") || Equals(key, n"right") {
                this.m_choice = VCTool.Wrap(this.m_choice + (Equals(key, n"left") ? -1 : 1), ArraySize(this.m_choiceIds));
                this.m_pending = !addons;
                this.m_pendingAt = this.Now() + 0.5;
            } else if addons && (Equals(key, n"enter") || Equals(key, n"down")) {
                if this.m_choice >= 0 && this.m_choice < ArraySize(this.m_choiceIds) {
                    this.ToggleKit(this.m_choiceIds[this.m_choice], this.m_choiceLabels[this.m_choice]);
                }
            } else if Equals(key, n"enter") || Equals(key, n"down") {
                this.m_pending = false;
                this.Apply();
            } else if Equals(key, n"up") {
                if this.m_pending {
                    this.m_pending = false;
                    this.Apply();
                }
                // What can change may have changed with it (a new rim brings its own paints): the row again, on the
                // same kind.
                let keep = this.CurrentKind();
                this.MakeKinds();
                let k = ArrayFindFirst(this.m_kinds, keep);
                this.m_kind = k >= 0 ? k : 0;
                this.m_row = ArraySize(this.m_kinds) > 0 ? 1 : 0;
            }
        }
        this.Outline();
        this.Render();
    }

    // --- what the screens show ---

    private static func Pretty(text: String) -> String {
        return StrReplaceAll(text, "_", " ");
    }

    private func TabLabels() -> array<String> {
        let out: array<String>;
        for tab in this.m_tabs {
            ArrayPush(out, tab.label);
        }
        return out;
    }

    private func KindLabels() -> array<String> {
        let out: array<String>;
        for kind in this.m_kinds {
            ArrayPush(out, this.KindText(kind));
        }
        return out;
    }

    // Which choice is on the car now, for the "Fitted" tag.
    private func FittedChoice() -> Int32 {
        let tab = this.CurrentTab();
        if !IsDefined(this.m_car) || !IsDefined(tab) || this.m_kind < 0 || this.m_kind >= ArraySize(this.m_kinds) {
            return -1;
        }
        let kind = this.m_kinds[this.m_kind];
        if Equals(kind, n"addons") {
            return -1;
        }
        let now = this.NowOf(kind, tab, this.Catalog(), this.Build());
        return ArrayFindFirst(this.m_choiceIds, now);
    }

    // The key hints for the row you're on, or a message for a moment.
    private func HintText() -> String {
        if StrLen(this.m_note) > 0 && this.Now() < this.m_noteUntil {
            return this.m_note;
        }
        if !IsDefined(this.m_car) || ArraySize(this.m_tabs) == 0 {
            return "Switch weapons to put the tool down";
        }
        if this.m_row == 0 {
            return "Left / Right  part      Down  change it";
        }
        if this.m_row == 1 {
            if Equals(this.CurrentKind(), n"takeoff") {
                return "Down  take it off      Up  back";
            }
            return "Left / Right  what      Down  choose      Up  back";
        }
        if Equals(this.CurrentKind(), n"addons") {
            return "Left / Right  browse      Enter  on / off      Up  back      Backspace  undo";
        }
        if Equals(this.CurrentKind(), n"axles") {
            return "Left / Right  which wheels      Enter  choose      Up  back";
        }
        return "Left / Right  try on      Enter  now      Up  back      Backspace  undo";
    }

    private func Say(text: String) {
        this.m_note = text;
        this.m_noteUntil = this.Now() + 3.0;
    }

    private func Render() {
        this.RenderHud();
        if ArraySize(this.m_lines) == 0 {
            return;
        }
        if !IsDefined(this.m_car) || ArraySize(this.m_tabs) == 0 {
            this.SetLine(0, StrLen(this.m_hint) > 0 ? this.m_hint : "Aim at a car", true);
            this.SetLine(1, "", false);
            this.SetLine(2, "", false);
            this.SetLine(3, "", false);
            return;
        }
        let tabs = "";
        let i = 0;
        while i < ArraySize(this.m_tabs) {
            let label = this.m_tabs[i].label;
            tabs += (i > 0 ? "  " : "") + (i == this.m_tab ? "[" + label + "]" : label);
            i += 1;
        }
        this.SetLine(0, tabs, this.m_row == 0);
        if this.m_row == 0 {
            this.SetLine(1, "Down: change it", false);
            this.SetLine(2, "", false);
            this.SetLine(3, this.m_note, false);
            return;
        }
        let kinds = "";
        i = 0;
        while i < ArraySize(this.m_kinds) {
            let label = this.KindText(this.m_kinds[i]);
            kinds += (i > 0 ? "  " : "") + (i == this.m_kind ? "[" + label + "]" : label);
            i += 1;
        }
        this.SetLine(1, kinds, this.m_row == 1);
        if this.m_row == 1 {
            this.SetLine(2, "Down: choose", false);
            this.SetLine(3, "Up: back", false);
            return;
        }
        let n = ArraySize(this.m_choiceIds);
        let label = n > 0 ? VCTool.Pretty(this.m_choiceLabels[this.m_choice]) : "";
        this.SetLine(2, "< " + label + " >", true);
        this.SetLine(3, s"\(this.m_choice + 1) of \(n)" + (this.m_pending ? "  ..." : "") + "   Backspace undoes", false);
    }

    // --- the HUD panel (2026-11-07, for tonight: the stand-in's screen can't be seen) ---
    // A panel up and to the right of the crosshair, in the HUD's own font and cyan: the car's name, then the grid's
    // three rows (the one you're on marked by a bar and bright, the rest dimmed; the chosen item in each bright),
    // a bar filling while a choice rests, and the keys for the row you're on.

    private static func Cyan(alpha: Float) -> HDRColor {
        return new HDRColor(0.369, 0.965, 1.0, alpha);
    }

    private static func HudWidth() -> Float {
        return 440.0;
    }

    // At most three items of a row, centred on the chosen one, with < or > where more lie that way.
    private static func Window(labels: array<String>, chosen: Int32, out shown: array<String>, out shownChosen: Int32) {
        let n = ArraySize(labels);
        if n <= 3 {
            shown = labels;
            shownChosen = chosen;
            return;
        }
        let first = Max(0, Min(chosen - 1, n - 3));
        if first > 0 {
            ArrayPush(shown, "<");
        }
        let i = first;
        while i < first + 3 {
            if i == chosen {
                shownChosen = ArraySize(shown);
            }
            ArrayPush(shown, labels[i]);
            i += 1;
        }
        if first + 3 < n {
            ArrayPush(shown, ">");
        }
    }

    private static func HudText(parent: ref<inkCompoundWidget>, name: CName, size: Int32, style: CName, x: Float, y: Float) -> ref<inkText> {
        let text = new inkText();
        text.SetName(name);
        text.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        text.SetFontStyle(style);
        text.SetFontSize(size);
        text.SetLetterCase(textLetterCase.UpperCase);
        text.SetTintColor(VCTool.Cyan(1.0));
        text.SetAnchor(inkEAnchor.TopLeft);
        text.SetMargin(new inkMargin(x, y, 0.0, 0.0));
        text.Reparent(parent);
        return text;
    }

    private static func HudRow(parent: ref<inkCompoundWidget>, name: CName, x: Float, y: Float) -> ref<inkHorizontalPanel> {
        let row = new inkHorizontalPanel();
        row.SetName(name);
        row.SetAnchor(inkEAnchor.TopLeft);
        row.SetMargin(new inkMargin(x, y, 0.0, 0.0));
        row.Reparent(parent);
        return row;
    }

    private func EnsureHud() -> Bool {
        if IsDefined(this.m_hud) {
            return true;
        }
        let root = GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer").GetVirtualWindow();
        if !IsDefined(root) {
            return false;
        }
        // About one unit to a screen pixel at 1920 by 1200 (user's screenshot, 2026-11-07: the first panel, twice
        // this size, covered the minimap and the quest list). Right of the crosshair and a little below it, clear of
        // the minimap, the quest list and the weapon's corner.
        let panel = new inkCanvas();
        panel.SetName(n"vc_tool_hud");
        panel.SetAnchor(inkEAnchor.Centered);
        panel.SetAnchorPoint(new Vector2(0.0, 0.0));
        panel.SetSize(VCTool.HudWidth(), 172.0);
        panel.SetTranslation(new Vector2(120.0, 36.0));
        panel.Reparent(root);
        let back = new inkRectangle();
        back.SetName(n"back");
        back.SetSize(VCTool.HudWidth(), 172.0);
        back.SetTintColor(new HDRColor(0.02, 0.05, 0.07, 1.0));
        back.SetOpacity(0.74);
        back.Reparent(panel);
        let edge = new inkRectangle();
        edge.SetName(n"edge");
        edge.SetSize(3.0, 172.0);
        edge.SetTintColor(VCTool.Cyan(1.0));
        edge.SetOpacity(0.85);
        edge.Reparent(panel);
        let marker = new inkRectangle();
        marker.SetName(n"marker");
        marker.SetSize(4.0, 22.0);
        marker.SetTintColor(VCTool.Cyan(1.0));
        marker.Reparent(panel);
        this.m_hudMarker = marker;
        this.m_hudHeader = VCTool.HudText(panel, n"header", 17, n"Medium", 22.0, 8.0);
        this.m_hudTabs = VCTool.HudRow(panel, n"tabs", 22.0, 32.0);
        this.m_hudKinds = VCTool.HudRow(panel, n"kinds", 22.0, 62.0);
        this.m_hudChoice = VCTool.HudText(panel, n"choice", 27, n"Semi-Bold", 22.0, 92.0);
        let count = VCTool.HudText(panel, n"count", 17, n"Medium", 0.0, 0.0);
        count.SetAnchor(inkEAnchor.TopRight);
        count.SetAnchorPoint(new Vector2(1.0, 0.0));
        count.SetMargin(new inkMargin(0.0, 100.0, 14.0, 0.0));
        this.m_hudCount = count;
        let bar = new inkRectangle();
        bar.SetName(n"bar");
        bar.SetMargin(new inkMargin(22.0, 128.0, 0.0, 0.0));
        bar.SetSize(0.0, 2.0);
        bar.SetTintColor(VCTool.Cyan(1.0));
        bar.Reparent(panel);
        this.m_hudBar = bar;
        this.m_hudHint = VCTool.HudText(panel, n"hint", 15, n"Medium", 22.0, 140.0);
        this.m_hud = panel;
        this.m_hudTabsKey = "";
        this.m_hudKindsKey = "";
        return true;
    }

    private func HideHud() {
        if IsDefined(this.m_hud) {
            this.m_hud.SetVisible(false);
        }
    }

    // A row of items: rebuilt only when its labels change; the chosen one bright, all dimmer when it isn't your row.
    private func FillRow(row: wref<inkHorizontalPanel>, all: array<String>, allChosen: Int32, active: Bool, key: String) -> String {
        if !IsDefined(row) {
            return key;
        }
        let labels: array<String>;
        let chosen = -1;
        VCTool.Window(all, allChosen, labels, chosen);
        let joined = "";
        for label in labels {
            joined += label + "|";
        }
        if !Equals(joined, key) {
            row.RemoveAllChildren();
            for label in labels {
                let text = new inkText();
                text.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
                text.SetFontSize(22);
                text.SetLetterCase(textLetterCase.UpperCase);
                text.SetText(label);
                text.SetMargin(new inkMargin(0.0, 0.0, 18.0, 0.0));
                text.Reparent(row);
            }
        }
        let i = 0;
        while i < row.GetNumChildren() {
            let text = row.GetWidget(i) as inkText;
            if IsDefined(text) {
                let on = i == chosen;
                text.SetFontStyle(on ? n"Semi-Bold" : n"Medium");
                text.SetTintColor(on ? (active ? new HDRColor(0.95, 1.0, 1.0, 1.0) : VCTool.Cyan(1.0)) : VCTool.Cyan(1.0));
                text.SetOpacity(on ? 1.0 : (active ? 0.5 : 0.32));
            }
            i += 1;
        }
        return joined;
    }

    private func RenderHud() {
        if !this.m_held || !this.EnsureHud() {
            this.HideHud();
            return;
        }
        this.m_hud.SetVisible(true);
        let hasCar = IsDefined(this.m_car) && ArraySize(this.m_tabs) > 0;
        // The header: the car's name, and in a session whose car it is.
        if hasCar {
            let header = this.m_car.GetDisplayName();
            let engine = VCEngine.Get(this.GetGameInstance());
            let record = this.m_car.GetRecordID();
            if engine.InSession() && !engine.Owns(record) {
                let owner = VCShop.Get(this.GetGameInstance()).OwnerName(record);
                header += "  -  " + (StrLen(owner) > 0 ? owner + "'s car" : "a partner's car");
            }
            this.m_hudHeader.SetText(header);
            this.m_hudHeader.SetOpacity(0.6);
        } else {
            this.m_hudHeader.SetText(StrLen(this.m_hint) > 0 ? this.m_hint : "Aim at a car");
            this.m_hudHeader.SetOpacity(1.0);
        }
        // Rows 1 and 2.
        let none: array<String>;
        this.m_hudTabsKey = this.FillRow(this.m_hudTabs, hasCar ? this.TabLabels() : none, this.m_tab, this.m_row == 0, this.m_hudTabsKey);
        let kinds = this.m_row >= 1 ? this.KindLabels() : none;
        this.m_hudKindsKey = this.FillRow(this.m_hudKinds, kinds, this.m_row >= 1 ? this.m_kind : -1, this.m_row == 1, this.m_hudKindsKey);
        // Row 3: the choice, how many, whether it's fitted.
        if this.m_row == 2 && ArraySize(this.m_choiceIds) > 0 {
            let label = VCTool.Pretty(this.m_choiceLabels[this.m_choice]);
            this.m_hudChoice.SetText("<  " + label + "  >");
            this.m_hudChoice.SetTintColor(new HDRColor(0.95, 1.0, 1.0, 1.0));
            let position = s"\(this.m_choice + 1) / \(ArraySize(this.m_choiceIds))";
            if Equals(this.CurrentKind(), n"addons") {
                let on = this.KitOn(this.m_choiceIds[this.m_choice]);
                this.m_hudCount.SetText((on ? "On   " : "Off   ") + position);
                this.m_hudCount.SetOpacity(on ? 1.0 : 0.55);
            } else {
                let fitted = this.FittedChoice() == this.m_choice;
                this.m_hudCount.SetText((fitted ? "Fitted   " : "") + position);
                this.m_hudCount.SetOpacity(fitted ? 1.0 : 0.55);
            }
        } else {
            this.m_hudChoice.SetText("");
            this.m_hudCount.SetText("");
        }
        // The resting bar: fills over the half second before a choice goes on.
        if this.m_pending {
            let left = MaxF(0.0, this.m_pendingAt - this.Now());
            this.m_hudBar.SetSize((VCTool.HudWidth() - 44.0) * (1.0 - left / 0.5), 2.0);
            this.m_hudBar.SetOpacity(0.9);
        } else {
            this.m_hudBar.SetSize(0.0, 2.0);
        }
        // The marker on the row you're on.
        let y = this.m_row == 0 ? 32.0 : (this.m_row == 1 ? 62.0 : 94.0);
        this.m_hudMarker.SetMargin(new inkMargin(9.0, y + 3.0, 0.0, 0.0));
        this.m_hudMarker.SetVisible(hasCar);
        // The hint row: a message for a moment, else the keys.
        let showingNote = StrLen(this.m_note) > 0 && this.Now() < this.m_noteUntil;
        this.m_hudHint.SetText(this.HintText());
        this.m_hudHint.SetTintColor(showingNote ? new HDRColor(1.0, 0.85, 0.45, 1.0) : VCTool.Cyan(1.0));
        this.m_hudHint.SetOpacity(showingNote ? 1.0 : 0.6);
    }
}

// The tool never fires: the weapon's state machine asks this before every kind of shot (probe, 2026-11-07).
@wrapMethod(WeaponTransition)
protected const func ShouldShoot(scriptInterface: ref<StateGameScriptInterface>) -> Bool {
    if VCTool.IsTool(this.GetWeaponObject(scriptInterface)) {
        return false;
    }
    return wrappedMethod(scriptInterface);
}

// The tool isn't put away by itself: out of combat in public the game lowers a weapon ("public safe") and after
// playerStateMachineWeapon.publicSafe.timeToAutoUnequipWeapon seconds sends an unequip request, which for the heavy
// slot drops it: the tool fell out of the user's hands "after a while" (2026-11-07). A weapon switch still drops it.
@wrapMethod(PublicSafeEvents)
private func RequestWeaponUnequipNotifyUpperBody(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) {
    if VCTool.IsTool(this.GetWeaponObject(scriptInterface)) {
        return;
    }
    wrappedMethod(stateContext, scriptInterface);
}

// The tool's screen: the gun screens' controller (ironsight.script), which many guns share, so only the tool's.
@wrapMethod(IronsightGameController)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    let weapon = this.GetOwnerEntity() as WeaponObject;
    if VCTool.IsTool(weapon) {
        VCTool.Get(weapon.GetGame()).BuildScreen(this.GetRootCompoundWidget());
    }
    return result;
}
