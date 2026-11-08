// Vehicle Customizer: the customization screen (vehicle-customizer/UX.md; state and actions in Shop.reds).
// A panel down the right of the screen in the game's own popup layer (Codeware's InGamePopup), with the mouse
// cursor, no blur and no slow motion, so the car stays in full view on the left and changes as you click. Tabs:
// style, parts, wheels, paint, add-ons, service, garage. Lists show parts by part number with where they come
// from, as UX.md asks; there are no pictures yet. Buttons along the bottom left step V round the car.
module VehicleCustomizer
import Codeware.UI.*

// One row of a list.
public class VCItem {
    public let id: CName;
    public let id2: CName;
    public let kind: Int32;
    public let main: String;
    public let right: String;
    public let sub: String;
    public let tags: array<String>;
    public let tagColors: array<Int32>;
    public let used: Bool;
    public let picked: Bool;
    public let indent: Int32;
    public let dim: Bool;
    public let code: Bool; // a part number or game name: shown as the game writes it, in lowercase

    public static func Make(id: CName, kind: Int32, main: String, right: String, sub: String) -> ref<VCItem> {
        let item = new VCItem();
        item.id = id;
        item.kind = kind;
        item.main = main;
        item.right = right;
        item.sub = sub;
        return item;
    }

    public func Tag(text: String, color: Int32) {
        if ArraySize(this.tags) < 3 && StrLen(text) > 0 {
            ArrayPush(this.tags, StrLen(text) > 34 ? StrLeft(text, 33) + "." : text);
            ArrayPush(this.tagColors, color);
        }
    }
}

// A scrolling list: a fixed set of row widgets showing the items from an offset.
public class VCList {
    public let key: String;
    public let root: ref<inkCanvas>;
    public let width: Float;
    public let rightWidth: Float;
    public let height: Float;
    public let capacity: Int32;
    public let items: array<ref<VCItem>>;
    public let offset: Int32;
    public let hovered: Int32;
    public let rows: array<ref<inkCanvas>>;
    public let bgs: array<ref<inkRectangle>>;
    public let accents: array<ref<inkRectangle>>;
    public let mains: array<ref<inkText>>;
    public let rights: array<ref<inkText>>;
    public let lines: array<ref<inkHorizontalPanel>>;
    public let subs: array<ref<inkText>>;
    public let tagMarks: array<ref<inkRectangle>>;
    public let tagTexts: array<ref<inkText>>;
    public let track: ref<inkRectangle>;
    public let bar: ref<inkRectangle>;
    public let empty: ref<inkText>;
}

public class VCScreenTick extends DelayCallback {
    public let screen: wref<VCScreen>;

    public func Call() {
        if IsDefined(this.screen) {
            this.screen.Tick();
        }
    }
}

public class VCScreen extends InGamePopup {
    private let m_shop: wref<VCShop>;
    private let m_showing: Bool;
    private let m_panel: ref<inkCanvas>;
    private let m_title: ref<inkText>;
    private let m_subtitle: ref<inkText>;
    private let m_tabBgs: array<ref<inkRectangle>>;
    private let m_tabTexts: array<ref<inkText>>;
    private let m_tabLines: array<ref<inkRectangle>>;
    private let m_aTitle: ref<inkText>;
    private let m_bTitle: ref<inkText>;
    private let m_bHint: ref<inkText>;
    private let m_acts: array<ref<inkCanvas>>;
    private let m_actIds: array<CName>;
    private let m_actOn: array<Bool>;
    private let m_steppers: array<ref<inkCanvas>>;
    private let m_stepLabels: array<ref<inkText>>;
    private let m_stepValues: array<ref<inkText>>;
    private let m_stepCount: Int32;
    private let m_a: ref<VCList>;
    private let m_b: ref<VCList>;
    private let m_message: ref<inkText>;
    private let m_views: array<ref<inkCanvas>>;
    private let m_wheelList: String;
    private let m_lastTab: Int32;
    private let m_lastRecord: TweakDBID;
    // What the screen is showing, worked out on each refresh.
    private let m_engine: ref<VCEngine>;
    private let m_car: ref<VehicleObject>;
    private let m_cat: CName;
    private let m_build: ref<VCBuild>;
    private let m_look: String;
    private let m_style: CName;
    private let m_partner: Bool;
    private let m_owner: String;
    private let m_coopNote: String;

    public func SetShop(shop: ref<VCShop>) {
        this.m_shop = shop;
        this.m_lastTab = -1;
        this.m_wheelList = "b";
    }

    public func IsShowing() -> Bool {
        return this.m_showing;
    }

    // --- the popup: cursor on, nothing slowed or blurred, no vignette ---

    public func UseCursor() -> Bool {
        return true;
    }

    // The game's own CrystalCoat color picker's queue. Codeware's in-game popups use "game_popup", a queue the game
    // never uses, and the world behind the panel was black or frozen, blocking or not (user, co-op test,
    // 2026-11-06); the picker is a blocking notification with the cursor, from the same popup manager, in the same
    // modal context and visual state, and the car stays live behind it. Blocking stays on: without it the cursor
    // never came and the mouse turned the camera (user).
    public func GetQueueName() -> CName {
        return this.Mode() == 4 ? n"game_popup" : n"VehicleVisualCustomization";
    }

    // Which setup this opening uses (Service tab, VCShop.popupMode): 1 the CrystalCoat picker's exactly, 2 the
    // picker's without blur, 3 blocking with no slow motion or blur, 4 Codeware's own in-game popup. Kept until we
    // know which keeps the world live behind the panel. All are blocking: a setup that wasn't (with the picker's
    // cursor event) left the panel impossible to use until a restart (user, 2026-11-06).
    private func Mode() -> Int32 {
        return IsDefined(this.m_shop) ? this.m_shop.popupMode : 1;
    }

    protected func CreateVignette() {}

    protected func CreateContainer() {
        let container = new inkCanvas();
        container.SetName(n"container");
        container.SetAnchor(inkEAnchor.Fill);
        container.Reparent(this.GetRootCompoundWidget());
        this.m_container = container;
        this.SetContainerWidget(container);
    }

    // The picker's slow motion ("radialMenu", as Codeware's), in setups 1, 2 and 4; NightCoop turns it off in co-op.
    protected func SetTimeDilation() {
        let mode = this.Mode();
        if mode == 1 || mode == 2 || mode == 4 {
            super.SetTimeDilation();
        }
    }

    // Closing always clears slow motion and blur, whichever setup opened the panel: something else blurs the world
    // behind a popup too, and setups that didn't clear it left the game blurry after closing (user, 2026-11-06).
    protected func ResetTimeDilation() {
        super.ResetTimeDilation();
    }

    protected func SetBackgroundBlur() {
        let mode = this.Mode();
        if mode == 1 || mode == 4 {
            super.SetBackgroundBlur();
        }
    }

    protected func ResetBackgroundBlur() {
        super.ResetBackgroundBlur();
    }


    protected cb func OnCreate() {
        super.OnCreate();
        this.Build();
    }

    protected cb func OnInitialize() {
        super.OnInitialize();
        // The mouse wheel comes as a relative event on PC (the game's gallery listens there); both, to be sure.
        this.RegisterToGlobalInputCallback(n"OnPostOnAxis", this, n"OnAxisInput");
        this.RegisterToGlobalInputCallback(n"OnPostOnRelative", this, n"OnAxisInput");
    }

    protected cb func OnShow() {
        super.OnShow();
        this.m_showing = true;
        this.Refresh();
        this.PlaySound(n"Button", n"OnPress");
        this.ScheduleTick();
    }

    protected cb func OnHide() {
        super.OnHide();
        this.m_showing = false;
        this.UnregisterFromGlobalInputCallback(n"OnPostOnAxis", this, n"OnAxisInput");
        this.UnregisterFromGlobalInputCallback(n"OnPostOnRelative", this, n"OnAxisInput");
        if IsDefined(this.m_shop) {
            this.m_shop.ScreenClosed(this);
        }
    }

    private func ScheduleTick() {
        let tick = new VCScreenTick();
        tick.screen = this;
        GameInstance.GetDelaySystem(this.GetGame()).DelayCallback(tick, 1.0, false);
    }

    // Once a second: the car may have arrived, left or been rebuilt, and the workshop log moves on.
    public func Tick() {
        if !this.m_showing {
            return;
        }
        this.Refresh();
        this.ScheduleTick();
    }

    // --- colours and building blocks ---

    public static func Color(code: Int32) -> HDRColor {
        if code == 1 {
            return HDRColor(0.368627, 0.964706, 1.0, 1.0); // cyan, the game's blue
        }
        if code == 2 {
            return HDRColor(1.1761, 0.3809, 0.3476, 1.0); // the game's red
        }
        if code == 3 {
            return HDRColor(1.1192, 0.8441, 0.2565, 1.0); // yellow
        }
        if code == 4 {
            return HDRColor(0.113725, 0.929412, 0.513726, 1.0); // green
        }
        if code == 5 {
            return HDRColor(0.52, 0.55, 0.6, 1.0); // grey
        }
        if code == 6 {
            return HDRColor(0.054902, 0.054902, 0.090196, 1.0); // background
        }
        if code == 7 {
            return HDRColor(0.411765, 0.086275, 0.090196, 1.0); // dark red
        }
        return HDRColor(0.92, 0.93, 0.95, 1.0); // white
    }

    private func Text(parent: ref<inkCompoundWidget>, x: Float, y: Float, w: Float, h: Float, size: Int32,
                      style: CName, color: Int32) -> ref<inkText> {
        let t = new inkText();
        t.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        t.SetFontStyle(style);
        t.SetFontSize(size);
        t.SetLetterCase(textLetterCase.UpperCase);
        t.SetTintColor(VCScreen.Color(color));
        t.SetAnchor(inkEAnchor.TopLeft);
        t.SetMargin(inkMargin(x, y, 0.0, 0.0));
        t.SetVerticalAlignment(textVerticalAlignment.Center);
        if w > 0.0 {
            t.SetSize(Vector2(w, h));
            t.SetOverflowPolicy(textOverflowPolicy.DotsEnd);
        } else {
            t.SetFitToContent(true);
        }
        t.Reparent(parent);
        return t;
    }

    private func Rect(parent: ref<inkCompoundWidget>, x: Float, y: Float, w: Float, h: Float, color: Int32,
                      opacity: Float) -> ref<inkRectangle> {
        let r = new inkRectangle();
        r.SetAnchor(inkEAnchor.TopLeft);
        r.SetMargin(inkMargin(x, y, 0.0, 0.0));
        r.SetSize(Vector2(w, h));
        r.SetTintColor(VCScreen.Color(color));
        r.SetOpacity(opacity);
        r.Reparent(parent);
        return r;
    }

    private func Canvas(parent: ref<inkCompoundWidget>, name: String, x: Float, y: Float, w: Float, h: Float) -> ref<inkCanvas> {
        let c = new inkCanvas();
        c.SetName(StringToName(name));
        c.SetAnchor(inkEAnchor.TopLeft);
        c.SetMargin(inkMargin(x, y, 0.0, 0.0));
        c.SetSize(Vector2(w, h));
        c.Reparent(parent);
        return c;
    }

    // Clicks and hovering come back to OnClick, OnHoverIn and OnHoverOut with the widget's name.
    private func Hook(widget: ref<inkWidget>) {
        widget.SetInteractive(true);
        widget.RegisterToCallback(n"OnRelease", this, n"OnClick");
        widget.RegisterToCallback(n"OnEnter", this, n"OnHoverIn");
        widget.RegisterToCallback(n"OnLeave", this, n"OnHoverOut");
    }

    // A button: child 0 its background, 1 its label, 2 the line under it.
    private func Button(parent: ref<inkCompoundWidget>, name: String, label: String, x: Float, y: Float, w: Float,
                        h: Float) -> ref<inkCanvas> {
        let c = this.Canvas(parent, name, x, y, w, h);
        this.Rect(c, 0.0, 0.0, w, h, 7, 0.45);
        let t = this.Text(c, 0.0, 0.0, w, h, 32, n"Semi-Bold", 2);
        t.SetHorizontalAlignment(textHorizontalAlignment.Center);
        t.SetText(label);
        this.Rect(c, 0.0, h - 3.0, w, 3.0, 2, 0.8);
        this.Hook(c);
        return c;
    }

    private func SetButton(button: ref<inkCanvas>, label: String, on: Bool) {
        let t = button.GetWidgetByIndex(1) as inkText;
        t.SetText(label);
        t.SetTintColor(VCScreen.Color(on ? 1 : 2));
        let line = button.GetWidgetByIndex(2) as inkRectangle;
        line.SetTintColor(VCScreen.Color(on ? 1 : 2));
    }

    private func ButtonHover(button: ref<inkWidget>, hover: Bool) {
        let c = button as inkCanvas;
        if IsDefined(c) && c.GetNumChildren() > 0 {
            c.GetWidgetByIndex(0).SetOpacity(hover ? 0.95 : 0.45);
        }
    }

    // --- building the panel ---

    private func Build() {
        let root = this.GetContainerWidget();
        let panel = new inkCanvas();
        panel.SetName(n"panel");
        panel.SetAnchor(inkEAnchor.TopRight);
        panel.SetAnchorPoint(Vector2(1.0, 0.0));
        panel.SetMargin(inkMargin(0.0, 70.0, 60.0, 0.0));
        panel.SetSize(Vector2(1580.0, 2020.0));
        panel.Reparent(root);
        this.m_panel = panel;
        // Background, a red edge on the left and a bar along the top.
        this.Rect(panel, 0.0, 0.0, 1580.0, 2020.0, 6, 0.9);
        this.Rect(panel, 0.0, 0.0, 6.0, 2020.0, 2, 0.9);
        this.Rect(panel, 0.0, 0.0, 1580.0, 6.0, 2, 0.9);
        this.Rect(panel, 1180.0, 18.0, 360.0, 4.0, 1, 0.6);

        let kicker = this.Text(panel, 44.0, 30.0, 1100.0, 40.0, 30, n"Semi-Bold", 2);
        kicker.SetText("Mechanic terminal  //  vehicle customizer");
        this.m_title = this.Text(panel, 44.0, 70.0, 1490.0, 100.0, 86, n"Bold", 0);
        this.m_subtitle = this.Text(panel, 46.0, 172.0, 1490.0, 44.0, 34, n"Medium", 1);

        let tabs = ["Style", "Parts", "Wheels", "Paint", "Add-ons", "Service", "Garage"];
        let i = 0;
        while i < ArraySize(tabs) {
            let tab = this.Canvas(panel, "tab_" + ToString(i), 44.0 + Cast<Float>(i) * 214.0, 240.0, 204.0, 72.0);
            ArrayPush(this.m_tabBgs, this.Rect(tab, 0.0, 0.0, 204.0, 72.0, 1, 0.0));
            let label = this.Text(tab, 0.0, 0.0, 204.0, 68.0, 36, n"Semi-Bold", 5);
            label.SetHorizontalAlignment(textHorizontalAlignment.Center);
            label.SetText(tabs[i]);
            ArrayPush(this.m_tabTexts, label);
            ArrayPush(this.m_tabLines, this.Rect(tab, 0.0, 68.0, 204.0, 4.0, 2, 0.0));
            this.Hook(tab);
            i += 1;
        }
        this.Rect(panel, 44.0, 312.0, 1492.0, 2.0, 5, 0.5);

        // Left column: a title and list A.
        this.m_aTitle = this.Text(panel, 44.0, 336.0, 520.0, 44.0, 30, n"Semi-Bold", 5);
        this.m_a = this.MakeList(panel, "a", 44.0, 392.0, 540.0, 160.0, 1420.0);

        // Right column: title, hint, action buttons, steppers and list B.
        this.m_bTitle = this.Text(panel, 620.0, 330.0, 916.0, 56.0, 46, n"Semi-Bold", 1);
        this.m_bHint = this.Text(panel, 620.0, 386.0, 916.0, 36.0, 28, n"Medium", 5);
        this.m_bHint.SetLetterCase(textLetterCase.OriginalCase);
        i = 0;
        while i < 5 {
            ArrayPush(this.m_acts, this.Button(panel, "act_" + ToString(i), "", 620.0 + Cast<Float>(i) * 186.0, 434.0, 174.0, 64.0));
            ArrayPush(this.m_actIds, n"");
            ArrayPush(this.m_actOn, false);
            i += 1;
        }
        i = 0;
        while i < 6 {
            let x = 620.0 + Cast<Float>(i % 2) * 466.0;
            let y = 516.0 + Cast<Float>(i / 2) * 78.0;
            let s = this.Canvas(panel, "stepper_" + ToString(i), x, y, 450.0, 68.0);
            this.Rect(s, 0.0, 0.0, 450.0, 68.0, 0, 0.04);
            ArrayPush(this.m_stepLabels, this.Text(s, 16.0, 0.0, 150.0, 68.0, 30, n"Semi-Bold", 5));
            ArrayPush(this.m_stepValues, this.Text(s, 160.0, 0.0, 130.0, 68.0, 34, n"Semi-Bold", 0));
            this.Button(s, "stp_m_" + ToString(i), "-", 300.0, 4.0, 68.0, 60.0);
            this.Button(s, "stp_p_" + ToString(i), "+", 376.0, 4.0, 68.0, 60.0);
            ArrayPush(this.m_steppers, s);
            i += 1;
        }
        this.m_b = this.MakeList(panel, "b", 620.0, 516.0, 916.0, 300.0, 1300.0);

        // Footer: what just happened, undo and close.
        this.Rect(panel, 44.0, 1846.0, 1492.0, 2.0, 5, 0.5);
        this.m_message = this.Text(panel, 44.0, 1858.0, 1492.0, 50.0, 32, n"Medium", 3);
        this.m_message.SetLetterCase(textLetterCase.OriginalCase);
        this.Button(panel, "ft_undo", "Undo", 44.0, 1924.0, 220.0, 70.0);
        this.Button(panel, "ft_close", "Close", 276.0, 1924.0, 220.0, 70.0);
        let keys = this.Text(panel, 520.0, 1924.0, 1016.0, 70.0, 28, n"Medium", 5);
        keys.SetHorizontalAlignment(textHorizontalAlignment.Right);
        let open = IsDefined(this.m_shop) ? this.m_shop.OpenKeyName() : "F7";
        keys.SetText(open + " or Esc closes  /  Ctrl+Z undoes  /  mouse wheel scrolls");

        // Viewpoints along the bottom left: V steps round the car.
        let views = new inkCanvas();
        views.SetName(n"views");
        views.SetAnchor(inkEAnchor.BottomLeft);
        views.SetAnchorPoint(Vector2(0.0, 1.0));
        // Well clear of the bottom: on the user's 32:9 screen the popup's canvas runs past it (2026-11-06).
        views.SetMargin(inkMargin(90.0, 0.0, 0.0, 260.0));
        views.SetSize(Vector2(1640.0, 130.0));
        views.Reparent(root);
        let viewLabel = this.Text(views, 0.0, 0.0, 600.0, 40.0, 28, n"Semi-Bold", 2);
        viewLabel.SetText("View the car from");
        let names = ["Front 3/4", "Front", "Side", "Rear 3/4", "Rear", "Other side", "Closer", "Farther"];
        i = 0;
        while i < ArraySize(names) {
            ArrayPush(this.m_views, this.Button(views, "view_" + ToString(i), names[i], Cast<Float>(i) * 202.0, 52.0, 192.0, 64.0));
            i += 1;
        }
    }

    private func MakeList(parent: ref<inkCompoundWidget>, key: String, x: Float, y: Float, w: Float, rightWidth: Float,
                          height: Float) -> ref<VCList> {
        let list = new VCList();
        list.key = key;
        list.width = w;
        list.rightWidth = rightWidth;
        list.hovered = -1;
        list.root = this.Canvas(parent, "list_" + key, x, y, w, height);
        let count = Cast<Int32>(height / 92.0);
        let r = 0;
        while r < count {
            let row = this.Canvas(list.root, key + "_" + ToString(r), 0.0, Cast<Float>(r) * 92.0, w - 20.0, 86.0);
            ArrayPush(list.bgs, this.Rect(row, 0.0, 0.0, w - 20.0, 86.0, 1, 0.0));
            ArrayPush(list.accents, this.Rect(row, 0.0, 0.0, 6.0, 86.0, 1, 1.0));
            ArrayPush(list.mains, this.Text(row, 26.0, 4.0, w - 80.0 - rightWidth, 48.0, 40, n"Medium", 0));
            let right = this.Text(row, w - 40.0 - rightWidth, 4.0, rightWidth, 48.0, 30, n"Semi-Bold", 5);
            right.SetHorizontalAlignment(textHorizontalAlignment.Right);
            right.SetLetterCase(textLetterCase.OriginalCase);
            ArrayPush(list.rights, right);
            let line = new inkHorizontalPanel();
            line.SetAnchor(inkEAnchor.TopLeft);
            line.SetMargin(inkMargin(26.0, 50.0, 0.0, 0.0));
            line.SetSize(Vector2(w - 60.0, 32.0));
            line.Reparent(row);
            ArrayPush(list.lines, line);
            let sub = this.Text(line, 0.0, 0.0, 0.0, 0.0, 27, n"Medium", 5);
            sub.SetVAlign(inkEVerticalAlign.Center);
            sub.SetLetterCase(textLetterCase.OriginalCase);
            ArrayPush(list.subs, sub);
            let t = 0;
            while t < 3 {
                let mark = new inkRectangle();
                mark.SetSize(Vector2(12.0, 12.0));
                mark.SetMargin(inkMargin(22.0, 0.0, 8.0, 0.0));
                mark.SetVAlign(inkEVerticalAlign.Center);
                mark.Reparent(line);
                ArrayPush(list.tagMarks, mark);
                let tag = this.Text(line, 0.0, 0.0, 0.0, 0.0, 26, n"Semi-Bold", 1);
                tag.SetVAlign(inkEVerticalAlign.Center);
                tag.SetLetterCase(textLetterCase.OriginalCase);
                ArrayPush(list.tagTexts, tag);
                t += 1;
            }
            this.Hook(row);
            ArrayPush(list.rows, row);
            r += 1;
        }
        list.track = this.Rect(list.root, w - 8.0, 0.0, 4.0, height, 5, 0.25);
        list.bar = this.Rect(list.root, w - 10.0, 0.0, 8.0, 100.0, 1, 0.9);
        list.empty = this.Text(list.root, 26.0, 10.0, w - 60.0, 50.0, 32, n"Medium", 5);
        list.empty.SetLetterCase(textLetterCase.OriginalCase);
        this.SetListArea(list, y, height);
        return list;
    }

    private func SetListArea(list: ref<VCList>, y: Float, height: Float) {
        let m = list.root.GetMargin();
        list.root.SetMargin(inkMargin(m.left, y, 0.0, 0.0));
        list.height = height;
        list.capacity = Min(ArraySize(list.rows), Cast<Int32>(height / 92.0));
        list.track.SetSize(Vector2(4.0, Cast<Float>(list.capacity) * 92.0 - 6.0));
    }

    // --- drawing a list ---

    private func RenderList(list: ref<VCList>) {
        let n = ArraySize(list.items);
        let maxOffset = Max(0, n - list.capacity);
        list.offset = Max(0, Min(list.offset, maxOffset));
        let r = 0;
        while r < ArraySize(list.rows) {
            let i = list.offset + r;
            let row = list.rows[r];
            if r < list.capacity && i < n {
                row.SetVisible(true);
                let item = list.items[i];
                let x = 26.0 + Cast<Float>(item.indent) * 40.0;
                let main = list.mains[r];
                main.SetText(item.main);
                main.SetLetterCase(item.code ? textLetterCase.OriginalCase : textLetterCase.UpperCase);
                main.SetMargin(inkMargin(x, 4.0, 0.0, 0.0));
                // a row with nothing on the right gets the whole width (the workshop log's long lines)
                main.SetSize(Vector2(list.width - 60.0 - (StrLen(item.right) > 0 ? list.rightWidth : 0.0) - x, 48.0));
                main.SetTintColor(VCScreen.Color(item.used ? 1 : item.dim ? 5 : 0));
                main.SetFontSize(item.indent > 0 ? 36 : 40);
                list.rights[r].SetText(item.right);
                list.rights[r].SetTintColor(VCScreen.Color(item.used ? 1 : 5));
                list.lines[r].SetMargin(inkMargin(x, 50.0, 0.0, 0.0));
                list.subs[r].SetText(item.sub);
                list.subs[r].SetVisible(StrLen(item.sub) > 0);
                let t = 0;
                while t < 3 {
                    let k = r * 3 + t;
                    let has = t < ArraySize(item.tags);
                    list.tagMarks[k].SetVisible(has);
                    list.tagTexts[k].SetVisible(has);
                    if has {
                        list.tagTexts[k].SetText(item.tags[t]);
                        list.tagTexts[k].SetTintColor(VCScreen.Color(item.tagColors[t]));
                        list.tagMarks[k].SetTintColor(VCScreen.Color(item.tagColors[t]));
                        // the first tag sits right at the start of the line when there's no sub text
                        list.tagMarks[k].SetMargin(inkMargin(t == 0 && StrLen(item.sub) == 0 ? 0.0 : 22.0, 0.0, 8.0, 0.0));
                    }
                    t += 1;
                }
                list.accents[r].SetVisible(item.used);
                this.StyleRow(list, r);
            } else {
                row.SetVisible(false);
            }
            r += 1;
        }
        let shown = Min(n, list.capacity);
        if n > list.capacity && n > 0 {
            let track = Cast<Float>(list.capacity) * 92.0 - 6.0;
            let barHeight = MaxF(40.0, track * Cast<Float>(shown) / Cast<Float>(n));
            let top = (track - barHeight) * Cast<Float>(list.offset) / Cast<Float>(maxOffset);
            list.bar.SetMargin(inkMargin(list.width - 10.0, top, 0.0, 0.0));
            list.bar.SetSize(Vector2(8.0, barHeight));
            list.bar.SetVisible(true);
            list.track.SetVisible(true);
        } else {
            list.bar.SetVisible(false);
            list.track.SetVisible(false);
        }
    }

    private func StyleRow(list: ref<VCList>, r: Int32) {
        let i = list.offset + r;
        if i >= ArraySize(list.items) {
            return;
        }
        let item = list.items[i];
        let hover = list.hovered == r;
        let bg = list.bgs[r];
        if item.picked {
            bg.SetTintColor(VCScreen.Color(1));
            bg.SetOpacity(hover ? 0.24 : 0.15);
        } else {
            bg.SetTintColor(VCScreen.Color(0));
            bg.SetOpacity(hover ? 0.08 : 0.0);
        }
    }

    // Scrolls so the first picked or used item shows.
    private func ShowPicked(list: ref<VCList>) {
        let i = 0;
        while i < ArraySize(list.items) {
            if list.items[i].picked || list.items[i].used {
                if i < list.offset || i >= list.offset + list.capacity {
                    list.offset = Max(0, i - list.capacity / 3);
                }
                return;
            }
            i += 1;
        }
        list.offset = 0;
    }

    // --- input ---

    protected cb func OnClick(evt: ref<inkPointerEvent>) -> Bool {
        if !evt.IsAction(n"click") || !IsDefined(this.m_shop) {
            return false;
        }
        let name = NameToString(evt.GetCurrentTarget().GetName());
        let number = StringToInt(StrAfterLast(name, "_"));
        this.PlaySound(n"Button", n"OnPress");
        if StrBeginsWith(name, "tab_") {
            this.m_shop.tab = number;
        } else if StrBeginsWith(name, "a_") {
            this.ClickA(this.m_a.offset + number);
        } else if StrBeginsWith(name, "b_") {
            this.ClickB(this.m_b.offset + number);
        } else if StrBeginsWith(name, "act_") {
            if number < ArraySize(this.m_actIds) {
                this.Act(this.m_actIds[number]);
            }
        } else if StrBeginsWith(name, "stp_") {
            this.Step(number, StrBeginsWith(name, "stp_p_") ? 1.0 : -1.0);
        } else if StrBeginsWith(name, "view_") {
            this.View(number);
        } else if Equals(name, "ft_undo") {
            this.m_shop.Undo();
        } else if Equals(name, "ft_close") {
            this.Close();
            return true;
        }
        this.Refresh();
        evt.Handle();
        return true;
    }

    protected cb func OnHoverIn(evt: ref<inkPointerEvent>) -> Bool {
        let widget = evt.GetCurrentTarget();
        let name = NameToString(widget.GetName());
        let number = StringToInt(StrAfterLast(name, "_"));
        if StrBeginsWith(name, "a_") {
            this.m_a.hovered = number;
            this.m_wheelList = "a";
            this.StyleRow(this.m_a, number);
        } else if StrBeginsWith(name, "b_") {
            this.m_b.hovered = number;
            this.m_wheelList = "b";
            this.StyleRow(this.m_b, number);
        } else if StrBeginsWith(name, "tab_") {
            this.m_tabBgs[number].SetOpacity(0.12);
        } else {
            this.ButtonHover(widget, true);
        }
    }

    protected cb func OnHoverOut(evt: ref<inkPointerEvent>) -> Bool {
        let widget = evt.GetCurrentTarget();
        let name = NameToString(widget.GetName());
        let number = StringToInt(StrAfterLast(name, "_"));
        if StrBeginsWith(name, "a_") {
            if this.m_a.hovered == number {
                this.m_a.hovered = -1;
            }
            this.StyleRow(this.m_a, number);
        } else if StrBeginsWith(name, "b_") {
            if this.m_b.hovered == number {
                this.m_b.hovered = -1;
            }
            this.StyleRow(this.m_b, number);
        } else if StrBeginsWith(name, "tab_") {
            this.m_tabBgs[number].SetOpacity(IsDefined(this.m_shop) && this.m_shop.tab == number ? 0.18 : 0.0);
        } else {
            this.ButtonHover(widget, false);
        }
    }

    protected cb func OnAxisInput(evt: ref<inkPointerEvent>) -> Bool {
        if !this.m_showing || !evt.IsAction(n"mouse_wheel") {
            return false;
        }
        let list = Equals(this.m_wheelList, "a") ? this.m_a : this.m_b;
        let amount = evt.GetAxisData();
        list.offset += amount > 0.0 ? -3 : 3;
        this.RenderList(list);
        return true;
    }

    // --- refreshing everything from the shop and the engine ---

    public func Refresh() {
        if !this.m_showing || !IsDefined(this.m_shop) {
            return;
        }
        let shop = this.m_shop;
        this.m_engine = shop.Engine();
        this.m_car = shop.Car();
        this.m_cat = shop.Catalog();
        this.m_build = VCBuild.Parse(shop.BuildText());
        this.m_look = shop.CurrentLook();
        this.m_style = VCData.StyleOf(this.m_cat, this.m_look);
        // In a session: a car that isn't ours, or ours showing a partner's version of it (a car both own is one car
        // with one look, and both keep its changes: user, 2026-11-07). Said in the player's words, not ours (user).
        this.m_partner = false;
        this.m_owner = "";
        this.m_coopNote = "";
        if IsDefined(this.m_car) && this.m_engine.InSession() {
            let record = this.m_car.GetRecordID();
            this.m_owner = shop.OwnerName(record);
            let theirs = StrLen(this.m_owner) > 0 ? this.m_owner + "'s" : "a partner's";
            if !this.m_engine.Owns(record) {
                this.m_partner = true;
                this.m_coopNote = StrLen(this.m_owner) > 0
                    ? this.m_owner + "'s car. Whatever you change here, " + this.m_owner + " keeps."
                    : "A partner's car. Whatever you change here, they keep.";
            } else if this.m_engine.HasSessionBuild(record) && !Equals(this.m_engine.WornText(record), this.m_engine.GetBuildText(record)) {
                this.m_coopNote = "You have this car too. This is " + theirs + " version: change anything and yours becomes this one.";
            }
        }
        let fresh = shop.tab != this.m_lastTab || !(shop.Record() == this.m_lastRecord);
        this.m_lastTab = shop.tab;
        this.m_lastRecord = shop.Record();

        this.RenderHeader();
        let i = 0;
        while i < ArraySize(this.m_tabTexts) {
            let on = i == shop.tab;
            this.m_tabTexts[i].SetTintColor(VCScreen.Color(on ? 0 : 5));
            this.m_tabLines[i].SetOpacity(on ? 1.0 : 0.0);
            this.m_tabBgs[i].SetOpacity(on ? 0.18 : 0.0);
            i += 1;
        }
        ArrayClear(this.m_a.items);
        ArrayClear(this.m_b.items);
        i = 0;
        while i < ArraySize(this.m_actIds) {
            this.m_actIds[i] = n"";
            this.m_actOn[i] = false;
            i += 1;
        }
        this.m_stepCount = 0;
        this.m_a.empty.SetText("");
        this.m_b.empty.SetText("");
        this.m_bHint.SetText("");
        this.m_bTitle.SetLetterCase(textLetterCase.UpperCase);

        if shop.tab == 6 {
            this.FillGarage();
        } else if shop.tab == 5 {
            this.FillService();
        } else if !IsNameValid(this.m_cat) || !IsDefined(this.m_car) {
            this.FillNoCar();
        } else if shop.tab == 0 {
            this.FillStyle();
        } else if shop.tab == 1 {
            this.FillParts();
        } else if shop.tab == 2 {
            this.FillWheels();
        } else if shop.tab == 3 {
            this.FillPaint();
        } else if shop.tab == 4 {
            this.FillAddOns();
        }
        if StrLen(this.m_coopNote) > 0 && shop.tab < 5 && StrLen(this.m_bHint.GetText()) == 0 {
            this.m_bHint.SetText(this.m_coopNote);
        }

        // Action buttons, steppers and the list below them.
        let acts = 0;
        i = 0;
        while i < ArraySize(this.m_acts) {
            let id = this.m_actIds[i];
            this.m_acts[i].SetVisible(IsNameValid(id));
            if IsNameValid(id) {
                this.SetButton(this.m_acts[i], this.ActLabel(id), this.m_actOn[i]);
                acts += 1;
            }
            i += 1;
        }
        i = 0;
        while i < ArraySize(this.m_steppers) {
            this.m_steppers[i].SetVisible(i < this.m_stepCount);
            i += 1;
        }
        let top = acts > 0 ? 516.0 : 440.0;
        if this.m_stepCount > 0 {
            let rows = (this.m_stepCount + 1) / 2;
            let y = 0;
            while y < ArraySize(this.m_steppers) {
                let m = this.m_steppers[y].GetMargin();
                this.m_steppers[y].SetMargin(inkMargin(m.left, top + Cast<Float>(y / 2) * 78.0, 0.0, 0.0));
                y += 1;
            }
            top += Cast<Float>(rows) * 78.0 + 12.0;
        }
        this.SetListArea(this.m_b, top, 1830.0 - top);

        if fresh {
            this.ShowPicked(this.m_a);
            this.ShowPicked(this.m_b);
        }
        this.m_a.empty.SetVisible(ArraySize(this.m_a.items) == 0);
        this.m_b.empty.SetVisible(ArraySize(this.m_b.items) == 0);
        this.RenderList(this.m_a);
        this.RenderList(this.m_b);
        this.m_message.SetText(shop.Message());

        let onFoot = true;
        let player = this.GetPlayer();
        if IsDefined(player) && IsDefined(player.GetMountedVehicle()) {
            onFoot = false;
        }
        for view in this.m_views {
            view.SetOpacity(onFoot && IsDefined(this.m_car) ? 1.0 : 0.35);
        }
    }

    private func RenderHeader() {
        let shop = this.m_shop;
        if IsNameValid(this.m_cat) {
            this.m_title.SetText(VCData.Text(this.m_cat, "label"));
            // Whose car it is, in the player's words: which of a model's copies it is stays out of sight (user,
            // 2026-11-07).
            let line = "Not yours";
            if this.m_engine.Owns(shop.Record()) {
                line = "Yours";
            } else if this.m_partner {
                line = StrLen(this.m_owner) > 0 ? this.m_owner + "'s" : "A partner's";
            }
            if IsNameValid(this.m_style) {
                line += "  /  " + VCData.Text(this.m_cat, "style." + NameToString(this.m_style) + ".label")
                    + " (" + NameToString(this.m_style) + ")";
            }
            if !IsDefined(this.m_car) {
                line += "  /  not here: bring it from the garage tab";
            } else if this.m_engine.PartnerCount() > 0 {
                line += s"  /  partners here: \(this.m_engine.PartnerCount())";
            }
            this.m_subtitle.SetText(line);
        } else if StrLen(shop.Foreign()) > 0 {
            this.m_title.SetText(shop.Foreign());
            this.m_subtitle.SetText("Not one of the shop's cars: buy one in the garage tab");
        } else {
            this.m_title.SetText("No car");
            this.m_subtitle.SetText("Get in one of your shop cars, look at it, or buy one in the garage tab");
        }
    }

    private func FillNoCar() {
        this.m_aTitle.SetText("");
        this.m_bTitle.SetText("No car to work on");
        this.m_bHint.SetText("Get in one of your shop cars, look at it, or buy or bring one in the garage tab.");
        this.m_b.empty.SetText("Nothing here yet.");
    }

    // --- reading the catalog ---

    private func Label(path: String) -> String {
        return VCData.Text(this.m_cat, path + ".label");
    }

    private func Code(path: String) -> String {
        return VCData.Text(this.m_cat, path + ".code");
    }

    // The option a slot has on the car now: the build's choice, else the style's own.
    private func OptionInEffect(slot: CName) -> CName {
        let i = this.m_build.SlotIndex(slot);
        if i >= 0 {
            return this.m_build.options[i];
        }
        return VCData.StyleOption(this.m_cat, this.m_style, slot);
    }

    private func Short(look: String) -> String {
        let s = look;
        let i = StrFindFirst(s, "__");
        if i >= 0 {
            s = StrRight(s, StrLen(s) - i - 2);
        }
        if StrBeginsWith(s, "basic_") {
            s = StrRight(s, StrLen(s) - 6);
        }
        return s;
    }

    // Where a part or kit comes from, as tags: another car, this style, another style, another look, a wreck.
    private func OriginTags(item: ref<VCItem>, key: String) {
        let car = VCData.Text(this.m_cat, key + ".vehicle");
        let mine = false;
        let otherStyle = "";
        let look = "";
        let wreck = false;
        for origin in VCData.Names(this.m_cat, key + ".origins") {
            let text = NameToString(origin);
            if StrBeginsWith(text, "style:") {
                let style = StrAfterFirst(text, ":");
                if Equals(style, NameToString(this.m_style)) {
                    mine = true;
                } else if StrLen(otherStyle) == 0 {
                    otherStyle = this.Label("style." + style);
                }
            } else if StrBeginsWith(text, "look:") {
                if StrLen(look) == 0 {
                    look = StrAfterFirst(text, ":");
                }
            } else if StrBeginsWith(text, "wreck:") {
                wreck = true;
            }
        }
        if StrLen(car) > 0 {
            item.Tag("Other car: " + car, 3);
        }
        if mine {
            item.Tag("This style", 4);
        }
        if StrLen(otherStyle) > 0 {
            item.Tag("Style: " + otherStyle, 4);
        }
        if StrLen(look) > 0 && !mine && StrLen(otherStyle) == 0 {
            item.Tag("Look: " + look, 1);
        }
        if wreck && ArraySize(item.tags) == 0 {
            item.Tag("From a wreck", 5);
        }
    }

    private func Add(list: ref<VCList>, item: ref<VCItem>) {
        ArrayPush(list.items, item);
    }

    // --- style ---

    private func FillStyle() {
        let shop = this.m_shop;
        let shown = IsNameValid(shop.styleShown) ? shop.styleShown : this.m_style;
        this.m_aTitle.SetText("Styles");
        for style in VCData.Names(this.m_cat, "styles") {
            let key = "style." + NameToString(style);
            let looks = VCData.Names(this.m_cat, key + ".looks");
            let item = VCItem.Make(style, 0, this.Label(key), "", s"\(ArraySize(looks)) finishes");
            item.used = Equals(style, this.m_style);
            item.picked = Equals(style, shown);
            this.Add(this.m_a, item);
        }
        let key = "style." + NameToString(shown);
        this.m_bTitle.SetText("Finishes: " + this.Label(key));
        this.m_bHint.SetText("A style is the version of the car; its finishes are the factory's paint jobs for it. Click to put one on.");
        for look in VCData.Names(this.m_cat, key + ".looks") {
            let item = VCItem.Make(look, 1, this.Short(NameToString(look)), "", "");
            item.code = true;
            item.used = Equals(NameToString(look), this.m_look);
            item.picked = item.used;
            if Equals(look, VCData.Name(this.m_cat, key + ".base")) {
                item.right = "Base";
            }
            this.Add(this.m_b, item);
        }
    }

    // --- parts ---

    private func FillParts() {
        let shop = this.m_shop;
        let slots = this.PartSlots();
        if shop.slotIndex >= ArraySize(slots) {
            shop.slotIndex = 0;
        }
        this.m_aTitle.SetText(s"Parts (\(ArraySize(slots)))");
        let i = 0;
        while i < ArraySize(slots) {
            let slot = slots[i];
            let chosen = this.m_build.SlotIndex(slot) >= 0;
            let inEffect = this.OptionInEffect(slot);
            let sub = IsNameValid(inEffect) ? this.Code("option." + NameToString(inEffect)) : "None on this style";
            let item = VCItem.Make(slot, 0, this.Label("slot." + NameToString(slot)), chosen ? "Changed" : "", sub);
            item.used = chosen;
            item.picked = i == shop.slotIndex;
            this.Add(this.m_a, item);
            i += 1;
        }
        if ArraySize(slots) == 0 {
            this.m_a.empty.SetText("This car has no parts to swap.");
            return;
        }
        let slot = slots[shop.slotIndex];
        let key = "slot." + NameToString(slot);
        let options = VCData.Names(this.m_cat, key + ".options");
        let own = VCData.StyleOption(this.m_cat, this.m_style, slot);
        let chosenIndex = this.m_build.SlotIndex(slot);
        let chosen = chosenIndex >= 0 ? this.m_build.options[chosenIndex] : n"";
        this.m_bTitle.SetText(this.Label(key));
        this.m_bHint.SetText(s"\(ArraySize(options)) to choose from. Click one to try it on; every part says where it comes from.");
        let first = VCItem.Make(n"", 0, IsNameValid(own) ? "Style's own" : "None", "",
            IsNameValid(own) ? this.Code("option." + NameToString(own)) : "This style has no part here");
        first.used = !IsNameValid(chosen);
        first.picked = first.used;
        this.Add(this.m_b, first);
        for option in options {
            let okey = "option." + NameToString(option);
            let item = VCItem.Make(option, 1, this.Code(okey), Equals(option, own) ? "Stock" : "", "");
            item.code = true;
            this.OriginTags(item, okey);
            item.used = Equals(option, chosen);
            item.picked = item.used;
            this.Add(this.m_b, item);
        }
    }

    // --- wheels ---

    // The rim on an axle (its set's id), which the rims' paints come from.
    private func AxleSet(front: Bool) -> CName {
        return front ? this.m_build.rimFront : this.m_build.rimBack;
    }

    private func AxleTire(front: Bool) -> CName {
        return front ? this.m_build.tireFront : this.m_build.tireBack;
    }

    private func SetLabel(set: CName, tire: Bool) -> String {
        return IsNameValid(set) ? TweakDBInterface.GetString(VCData.WheelKey(set, tire ? "tireLabel" : "rimLabel"), NameToString(set)) : "Car's own";
    }

    // The slots the Parts and Paint tabs list: every slot but the rims' and tires' the Wheels tab stands for (one place
    // per option, 2026-11-07).
    private func PartSlots() -> array<CName> {
        let out: array<CName>;
        for slot in VCData.Names(this.m_cat, "slots") {
            if !VCEngine.IsWheelSlot(this.m_cat, slot) {
                ArrayPush(out, slot);
            }
        }
        return out;
    }

    private func FitText(fit: Vector4) -> String {
        let size = fit.X <= 0.0 ? 100.0 : fit.X;
        let width = fit.Y <= 0.0 ? 100.0 : fit.Y;
        return FloatToStringPrec(size, 0) + "% / " + FloatToStringPrec(width, 0) + "%";
    }

    // Rims and tires apart (2026-11-07): the left list picks rims or tires and the axle, the right one lists them,
    // this car's own first, then every other vehicle's, each scaled to fit.
    private func FillWheels() {
        let shop = this.m_shop;
        let kind = NameToString(VCData.Name(this.m_cat, "wheelKind"));
        let own = TweakDBInterface.GetVector3Array(VCData.Key(this.m_cat, "wheelFit"));
        this.m_aTitle.SetText("Rims and tires");
        let ids = [n"rim_all", n"rim_f", n"rim_b", n"tire_all", n"tire_f", n"tire_b"];
        let names = ["Rims: all four", "Rims: front", "Rims: back", "Tires: all four", "Tires: front", "Tires: back"];
        let tireRows = !Equals(shop.wheelPart, n"rim");
        let i = 0;
        while i < 6 {
            let tire = i >= 3;
            let axle = i % 3 == 0 ? n"all" : (i % 3 == 1 ? n"f" : n"b");
            let front = !Equals(axle, n"b");
            let differ = tire ? !Equals(this.m_build.tireFront, this.m_build.tireBack) : !Equals(this.m_build.rimFront, this.m_build.rimBack);
            let sub = Equals(axle, n"all") && differ ? "Front and back differ"
                : this.SetLabel(tire ? this.AxleTire(front) : this.AxleSet(front), tire);
            let axleFit = front ? this.m_build.fitFront : this.m_build.fitBack;
            let right = tire ? this.FitText(axleFit) : FloatToStringPrec(axleFit.Z <= 0.0 ? 100.0 : axleFit.Z, 0) + "% wide";
            let item = VCItem.Make(ids[i], 0, names[i], right, sub);
            item.picked = Equals(axle, shop.axle) && Equals(tire, tireRows);
            item.used = item.picked;
            this.Add(this.m_a, item);
            i += 1;
        }
        if StrLen(kind) == 0 || ArraySize(own) < 2 {
            this.m_bTitle.SetText("Wheels");
            this.m_b.empty.SetText("No wheel sizes for this vehicle in the catalog.");
            return;
        }
        let front = !Equals(shop.axle, n"b");
        let fit = front ? this.m_build.fitFront : this.m_build.fitBack;
        let ref = front ? own[0] : own[1];
        let current = tireRows ? this.AxleTire(front) : this.AxleSet(front);
        let other = tireRows ? this.AxleTire(!front) : this.AxleSet(!front);
        // With the tires, the wheel's size (the rim follows the tire's inside) and the tire's width; with the rims, the
        // rim's width. Each width is its part's alone, to match one to the other (user, 2026-11-07).
        if tireRows {
            this.m_stepCount = 2;
            this.m_stepLabels[0].SetText("Size");
            this.m_stepValues[0].SetText(FloatToStringPrec(fit.X <= 0.0 ? 100.0 : fit.X, 0) + "%");
            this.m_stepLabels[1].SetText("Width");
            this.m_stepValues[1].SetText(FloatToStringPrec(fit.Y <= 0.0 ? 100.0 : fit.Y, 0) + "%");
            this.m_actIds[0] = n"ownsize";
        } else {
            this.m_stepCount = 1;
            this.m_stepLabels[0].SetText("Width");
            this.m_stepValues[0].SetText(FloatToStringPrec(fit.Z <= 0.0 ? 100.0 : fit.Z, 0) + "%");
            this.m_actIds[0] = n"ownrimwidth";
        }
        this.m_actIds[1] = n"fine";
        this.m_actOn[1] = shop.fine;
        let list = VCWheels.List(this.m_cat, tireRows);
        let label = tireRows ? "tireLabel" : "rimLabel";
        this.m_bTitle.SetText(tireRows ? s"Tires (\(ArraySize(list) - 1))" : s"Rims (\(ArraySize(list) - 1))");
        this.m_bHint.SetText(tireRows
            ? s"This car's own: \(FloatToStringPrec(ref.X * 200.0, 0)) x \(FloatToStringPrec(ref.Y * 100.0, 0)) cm. A new tire is fitted to it and to the rim automatically; adjust from there."
            : "This car's own first, then every other vehicle's. A new rim is fitted to its tire automatically; adjust the width from there.");
        let mine = VCData.Names(this.m_cat, tireRows ? "ownTires" : "ownRims");
        for id in list {
            let item: ref<VCItem>;
            if !IsNameValid(id) {
                item = VCItem.Make(n"", 0, "Car's own", "", tireRows ? "The car's own tires" : "The car's own rims");
            } else {
                item = VCItem.Make(id, 1, TweakDBInterface.GetString(VCData.WheelKey(id, label), NameToString(id)), "", "");
                if ArrayContains(mine, id) {
                    item.Tag("This car's", 4);
                }
                if !tireRows {
                    let paintList = TweakDBInterface.GetCNameArray(VCData.WheelKey(id, "paints"));
                    let paints = ArraySize(paintList);
                    if paints > 0 {
                        item.Tag(s"\(paints) paints", 1);
                    }
                }
                if Equals(shop.axle, n"all") && Equals(id, other) && !Equals(id, current) {
                    item.Tag("On the back", 4);
                }
            }
            item.used = Equals(id, current);
            item.picked = item.used;
            this.Add(this.m_b, item);
        }
    }

    // --- paint ---

    private func PaintsOf(target: CName) -> array<CName> {
        let t = NameToString(target);
        if Equals(t, "car") {
            let body = this.OptionInEffect(n"base.body");
            if IsNameValid(body) {
                return VCData.Names(this.m_cat, "option." + NameToString(body) + ".paints");
            }
            for slot in VCData.Names(this.m_cat, "slots") {
                let option = this.OptionInEffect(slot);
                let paints = VCData.Names(this.m_cat, "option." + NameToString(option) + ".paints");
                if ArraySize(paints) > 0 {
                    return paints;
                }
            }
            let none: array<CName>;
            return none;
        }
        if Equals(t, "rim_f") || Equals(t, "rim_b") {
            let set = this.AxleSet(Equals(t, "rim_f"));
            if IsNameValid(set) {
                return TweakDBInterface.GetCNameArray(VCData.WheelKey(set, "paints"));
            }
            let rim = this.OptionInEffect(n"wheel.wheel");
            return VCData.Names(this.m_cat, "option." + NameToString(rim) + ".paints");
        }
        return VCData.Names(this.m_cat, "option." + NameToString(this.OptionInEffect(target)) + ".paints");
    }

    private func PaintNow(target: CName) -> CName {
        let t = NameToString(target);
        if Equals(t, "car") {
            return this.m_build.paint;
        }
        if Equals(t, "rim_f") {
            return this.m_build.wheelPaintFront;
        }
        if Equals(t, "rim_b") {
            return this.m_build.wheelPaintBack;
        }
        let i = this.m_build.SlotIndex(target);
        return i >= 0 ? this.m_build.paints[i] : n"";
    }

    private func FillPaint() {
        let shop = this.m_shop;
        this.m_aTitle.SetText("What to paint");
        let targets: array<CName>;
        let labels: array<String>;
        ArrayPush(targets, n"car");
        ArrayPush(labels, "Whole car");
        ArrayPush(targets, n"rim_f");
        ArrayPush(labels, "Rims: front");
        ArrayPush(targets, n"rim_b");
        ArrayPush(labels, "Rims: back");
        for slot in this.PartSlots() {
            let option = this.OptionInEffect(slot);
            let offered = VCData.Names(this.m_cat, "option." + NameToString(option) + ".paints");
            if IsNameValid(option) && ArraySize(offered) > 0 {
                ArrayPush(targets, slot);
                ArrayPush(labels, this.Label("slot." + NameToString(slot)));
            }
        }
        if !ArrayContains(targets, shop.paintTarget) {
            shop.paintTarget = n"car";
        }
        let i = 0;
        while i < ArraySize(targets) {
            let now = this.PaintNow(targets[i]);
            let item = VCItem.Make(targets[i], 0, labels[i], "", IsNameValid(now) ? NameToString(now) : "As it comes");
            item.used = IsNameValid(now);
            item.picked = Equals(targets[i], shop.paintTarget);
            this.Add(this.m_a, item);
            i += 1;
        }
        let target = shop.paintTarget;
        let now = this.PaintNow(target);
        let paints = this.PaintsOf(target);
        let isCar = Equals(target, n"car");
        this.m_bTitle.SetText(labels[ArrayFindFirst(targets, target)]);
        this.m_bHint.SetText(isCar
            ? "Goes on every panel that has this paint; panels painted on their own keep theirs."
            : s"\(ArraySize(paints)) paints for this part. Click one to put it on.");
        let first = VCItem.Make(n"", 0, isCar ? "The finish's own" : "As it comes", "", "");
        first.used = !IsNameValid(now);
        first.picked = first.used;
        this.Add(this.m_b, first);
        let defaultPaint = n"";
        if !isCar && !StrBeginsWith(NameToString(target), "rim_") {
            defaultPaint = VCData.Name(this.m_cat, "option." + NameToString(this.OptionInEffect(target)) + ".defaultPaint");
        }
        for paint in paints {
            let item = VCItem.Make(paint, 1, NameToString(paint), Equals(paint, defaultPaint) ? "Default" : "", "");
            item.code = true;
            item.used = Equals(paint, now);
            item.picked = item.used;
            this.Add(this.m_b, item);
        }
        if ArraySize(paints) == 0 {
            this.m_b.empty.SetText("No paints offered here.");
        }
    }

    // --- add-ons ---

    private func KitCodes(kit: CName) -> array<String> {
        return TweakDBInterface.GetStringArray(VCData.Key(this.m_cat, "kit." + NameToString(kit) + ".codes"));
    }

    private func FillAddOns() {
        let shop = this.m_shop;
        let kits = VCData.Names(this.m_cat, "kits");
        if shop.kitIndex >= ArraySize(kits) {
            shop.kitIndex = 0;
        }
        let fitted = 0;
        let i = 0;
        while i < ArraySize(kits) {
            let kit = kits[i];
            let key = "kit." + NameToString(kit);
            let on = this.m_build.KitIndex(kit) >= 0;
            if on {
                fitted += 1;
            }
            let codes = this.KitCodes(kit);
            let item = VCItem.Make(kit, 0, this.Code(key), on ? "Fitted" : "",
                ArraySize(codes) == 1 ? "1 part" : s"\(ArraySize(codes)) parts");
            item.code = true;
            item.used = on;
            item.picked = i == shop.kitIndex;
            this.Add(this.m_a, item);
            i += 1;
        }
        this.m_aTitle.SetText(s"Add-ons (\(fitted) of \(ArraySize(kits)) fitted)");
        if ArraySize(kits) == 0 {
            this.m_a.empty.SetText("No add-ons for this car.");
            return;
        }
        let kit = kits[shop.kitIndex];
        let key = "kit." + NameToString(kit);
        let k = this.m_build.KitIndex(kit);
        let on = k >= 0;
        let codes = this.KitCodes(kit);
        if shop.kitPart >= ArraySize(codes) {
            shop.kitPart = -1;
        }
        this.m_bTitle.SetText(this.Code(key) + (on ? "" : "  (not fitted)"));
        this.m_bTitle.SetLetterCase(textLetterCase.OriginalCase);
        let madeFor = "";
        for what in VCData.Names(this.m_cat, key + ".madeFor") {
            let text = NameToString(what);
            let id = StrAfterFirst(text, ":");
            let name = StrBeginsWith(text, "kit:") ? this.Code("kit." + id) : this.Label("slot." + id);
            madeFor += (StrLen(madeFor) > 0 ? ", " : "") + name;
        }
        let hint = on ? "Pick the whole kit or one part, then move it with the buttons." : "Click it in the list again, or Fit, to put it on.";
        this.m_bHint.SetText(StrLen(madeFor) > 0 ? "Made to sit on " + madeFor + ". " + hint : hint);
        this.m_actIds[0] = n"kit";
        this.m_actOn[0] = on;
        if on {
            this.m_actIds[1] = n"fine";
            this.m_actOn[1] = shop.fine;
            this.m_actIds[2] = n"resetplace";
            // Where the chosen piece sits now.
            let move = shop.kitPart < 0 ? this.m_build.kitOffsets[k] : this.m_build.PartMove(kit, shop.kitPart);
            let turn = shop.kitPart < 0 ? this.m_build.KitTurn(k) : this.m_build.PartTurn(kit, shop.kitPart);
            this.m_stepCount = 6;
            let labels = ["Side", "Forward", "Up", "Turn", "Tilt", "Roll"];
            let values = [move.X * 100.0, move.Y * 100.0, move.Z * 100.0, move.W, turn.X, turn.Y];
            i = 0;
            while i < 6 {
                this.m_stepLabels[i].SetText(labels[i]);
                this.m_stepValues[i].SetText(FloatToStringPrec(values[i], 1) + (i < 3 ? " cm" : " deg"));
                i += 1;
            }
        }
        let whole = VCItem.Make(n"", -1, "Whole kit", "", s"Moves and turns its \(ArraySize(codes)) parts as one");
        whole.picked = shop.kitPart < 0;
        whole.used = on && whole.picked;
        whole.dim = !on;
        this.Add(this.m_b, whole);
        i = 0;
        while i < ArraySize(codes) {
            let moved = this.m_build.PartIndex(kit, i) >= 0;
            let item = VCItem.Make(n"", i, codes[i], moved ? "Moved" : "", "");
            item.code = true;
            item.indent = 1;
            item.picked = shop.kitPart == i;
            item.used = on && item.picked;
            item.dim = !on;
            this.Add(this.m_b, item);
            i += 1;
        }
        let tags = VCItem.Make(n"", -2, "Where it comes from", "", "");
        this.OriginTags(tags, key);
        if ArraySize(tags.tags) > 0 {
            tags.dim = true;
            this.Add(this.m_b, tags);
        }
    }

    // --- service ---

    private func FillService() {
        this.m_aTitle.SetText("Service");
        this.Add(this.m_a, VCItem.Make(n"quickfix", 0, "Quick fix", "", "Dents out, glass in, where it stands"));
        this.Add(this.m_a, VCItem.Make(n"refresh", 0, "Full refresh", "", "Brought round fresh, lost parts back"));
        this.Add(this.m_a, VCItem.Make(n"stock", 0, "Back to stock", "", "The style's own parts and paint"));
        this.Add(this.m_a, VCItem.Make(n"visit", 0, "Undo this visit", "", "As it was when you opened it"));
        this.Add(this.m_a, VCItem.Make(n"check", 0, "Check the build", "", "Every part checked on the car"));
        for item in this.m_a.items {
            item.dim = !IsDefined(this.m_car);
        }
        // The tool (Tool.reds): aim it at a car and change it part by part on its own screen.
        this.Add(this.m_a, VCItem.Make(n"tool", 0, "Take the tool", "", "Aim it at a car; arrow keys on its screen"));
        this.Add(this.m_a, VCItem.Make(n"painttool", 0, "Take the paint tool", "", "Load a colour, then click a part"));
        // How the screen opens, while we find what freezes the world behind it; each applies at the next opening.
        let setups = ["Picker, exactly", "Picker, no blur", "No slow motion", "Codeware's own"];
        let notes = ["Slow motion and blur, the picker's queue", "Slow motion, the picker's queue", "Blocking, nothing else",
            "Its queue, slow motion and blur"];
        let s = 0;
        while s < 4 {
            let row = VCItem.Make(StringToName("mode_" + ToString(s + 1)), 1, s"Setup \(s + 1): " + setups[s],
                this.m_shop.popupMode == s + 1 ? "In use" : "", notes[s]);
            row.used = this.m_shop.popupMode == s + 1;
            this.Add(this.m_a, row);
            s += 1;
        }
        this.m_bTitle.SetText("Workshop log");
        this.m_bHint.SetText("What the engine did, newest first.");
        let count = this.m_engine.GetLogCount();
        let n = count - 1;
        while n >= 0 && n >= count - 40 {
            let line = this.m_engine.GetLogLine(n);
            if StrLen(line) > 0 {
                let item = VCItem.Make(n"", -1, line, "", "");
                item.code = true;
                item.dim = true;
                this.Add(this.m_b, item);
            }
            n -= 1;
        }
    }

    // --- garage ---

    private static func Makers() -> array<String> {
        return ["archer", "arch", "brennan", "chevalier", "herrera", "kaukaz", "mahir", "makigai", "militech",
            "mizutani", "mt28", "q304", "quadra", "rayfield", "thorton", "villefort", "yaiba", "z71"];
    }

    private static func MakerOf(cat: CName) -> String {
        let text = NameToString(cat);
        let i = StrFindFirst(text, "_");
        return i > 0 ? StrLeft(text, i) : text;
    }

    private func FillGarage() {
        let shop = this.m_shop;
        let cats = VCData.Catalogs();
        let owned = shop.Owned();
        this.m_aTitle.SetText("Garage");
        let mine = VCItem.Make(n"mine", 0, "My cars", "", s"\(ArraySize(owned)) from the shop");
        mine.picked = Equals(shop.garagePick, n"mine");
        this.Add(this.m_a, mine);
        let makers = VCScreen.Makers();
        for cat in cats {
            if !ArrayContains(makers, VCScreen.MakerOf(cat)) {
                ArrayPush(makers, VCScreen.MakerOf(cat));
            }
        }
        for maker in makers {
            let count = 0;
            for cat in cats {
                if Equals(VCScreen.MakerOf(cat), maker) {
                    count += 1;
                }
            }
            if count > 0 {
                let item = VCItem.Make(StringToName(maker), 1, maker, ToString(count), "");
                item.picked = Equals(shop.garagePick, StringToName(maker));
                this.Add(this.m_a, item);
            }
        }
        if Equals(shop.garagePick, n"mine") {
            this.m_bTitle.SetText("My cars");
            this.m_bHint.SetText("Click one to work on it. Bring here calls it to you; Return it sells it back to the shop.");
            for record in owned {
                let cat = this.m_engine.CatalogOf(record);
                let build = VCBuild.Parse(this.m_engine.GetBuildText(record));
                let style = VCData.StyleOf(cat, NameToString(build.look));
                let id = StringToName(TDBID.ToStringDEBUG(record));
                let item = VCItem.Make(id, 2, VCData.Text(cat, "label"), "",
                    IsNameValid(style) ? VCData.Text(cat, "style." + NameToString(style) + ".label") : "Stock");
                if IsDefined(this.m_engine.VehicleOf(record)) {
                    item.Tag("Out", 4);
                }
                item.used = record == shop.Record();
                item.picked = Equals(id, shop.garageCar);
                if item.used && !IsNameValid(shop.garageCar) {
                    item.picked = true;
                    shop.garageCar = id;
                }
                this.Add(this.m_b, item);
            }
            if ArraySize(owned) == 0 {
                this.m_b.empty.SetText("None yet: pick a maker on the left and buy one.");
            }
            if IsNameValid(shop.garageCar) {
                this.m_actIds[0] = n"bring";
                this.m_actIds[1] = n"away";
                this.m_actIds[2] = n"return";
            }
            return;
        }
        let maker = NameToString(shop.garagePick);
        this.m_bTitle.SetText(maker);
        this.m_bHint.SetText("Pick a model, then a style, then Buy. It goes in your garage and comes to you.");
        for cat in cats {
            if Equals(VCScreen.MakerOf(cat), maker) {
                let styles = VCData.Names(cat, "styles");
                let have = 0;
                for record in VCData.Pool(cat) {
                    if ArrayContains(owned, record) {
                        have += 1;
                    }
                }
                let item = VCItem.Make(cat, 3, VCData.Text(cat, "label"), s"\(ArraySize(styles)) styles", NameToString(cat));
                if have > 0 {
                    item.Tag(s"You have \(have)", 4);
                }
                let open = Equals(cat, shop.garageModel);
                item.picked = open && !IsNameValid(shop.garageStyle);
                item.used = open;
                this.Add(this.m_b, item);
                if open {
                    for style in styles {
                        let key = "style." + NameToString(style);
                        let row = VCItem.Make(style, 4, VCData.Text(cat, key + ".label"), NameToString(style), "");
                        row.id2 = cat;
                        row.indent = 1;
                        row.picked = Equals(style, shop.garageStyle);
                        this.Add(this.m_b, row);
                    }
                }
            }
        }
        if IsNameValid(shop.garageModel) && IsNameValid(shop.garageStyle)
            && Equals(VCScreen.MakerOf(shop.garageModel), maker) {
            this.m_actIds[0] = n"buy";
            this.m_actOn[0] = true;
            let n = shop.FreeCopy(shop.garageModel);
            this.m_bHint.SetText(n >= 0 ? "Buy gets you one in this style: it goes in your garage and comes to you." : VCShop.SoldOut());
        }
    }

    // --- what clicks do ---

    private func ClickA(i: Int32) {
        if i < 0 || i >= ArraySize(this.m_a.items) {
            return;
        }
        let shop = this.m_shop;
        let item = this.m_a.items[i];
        let tab = shop.tab;
        if tab == 0 {
            shop.styleShown = item.id;
            if !Equals(item.id, this.m_style) {
                let key = "style." + NameToString(item.id);
                shop.ChooseLook(VCData.Name(this.m_cat, key + ".base"), this.Label(key));
            }
        } else if tab == 1 {
            shop.slotIndex = i;
            this.m_b.offset = 0;
            this.m_lastTab = -1;
        } else if tab == 2 {
            // rim_all, rim_f, rim_b, tire_all, tire_f, tire_b
            let what = NameToString(item.id);
            shop.wheelPart = StrBeginsWith(what, "rim") ? n"rim" : n"tire";
            shop.axle = StringToName(StrAfterFirst(what, "_"));
            this.m_b.offset = 0;
            this.m_lastTab = -1;
        } else if tab == 3 {
            shop.paintTarget = item.id;
            this.m_lastTab = -1;
        } else if tab == 4 {
            let kits = VCData.Names(this.m_cat, "kits");
            // A first click picks a kit (and fits it if it's off); clicking the picked one again takes it off.
            let on = this.m_build.KitIndex(item.id) >= 0;
            if i != shop.kitIndex {
                shop.kitIndex = i;
                shop.kitPart = -1;
                if !on {
                    shop.ToggleKit(item.id, item.main);
                }
            } else {
                shop.ToggleKit(item.id, item.main);
            }
            if i >= ArraySize(kits) {
                shop.kitIndex = 0;
            }
        } else if tab == 5 {
            let what = NameToString(item.id);
            if Equals(what, "quickfix") {
                shop.QuickFix();
            } else if Equals(what, "refresh") {
                shop.FullRefresh();
            } else if Equals(what, "stock") {
                shop.BackToStock();
            } else if Equals(what, "visit") {
                shop.UndoVisit();
            } else if Equals(what, "check") {
                shop.Check();
            } else if Equals(what, "tool") {
                if VCTool.Get(shop.GetGameInstance()).Give() {
                    shop.Say("The tool is in your hands: aim it at a car.");
                    this.Close();
                } else {
                    shop.Say("The tool couldn't be handed over.");
                }
            } else if Equals(what, "painttool") {
                if VCPaintTool.Get(shop.GetGameInstance()).Give() {
                    shop.Say("The paint tool is in your hands: load a colour.");
                    this.Close();
                } else {
                    shop.Say("The paint tool couldn't be handed over.");
                }
            } else if StrBeginsWith(what, "mode_") {
                shop.popupMode = StringToInt(StrAfterFirst(what, "_"));
                shop.Say(s"Setup \(shop.popupMode) is used from the next opening: close and press F7 again.");
            }
        } else if tab == 6 {
            shop.garagePick = item.id;
            shop.garageStyle = n"";
            this.m_lastTab = -1;
        }
    }

    private func ClickB(i: Int32) {
        if i < 0 || i >= ArraySize(this.m_b.items) {
            return;
        }
        let shop = this.m_shop;
        let item = this.m_b.items[i];
        let tab = shop.tab;
        if tab == 6 {
            if item.kind == 2 {
                shop.garageCar = item.id;
                shop.SetTarget(TDBID.Create(NameToString(item.id)));
            } else if item.kind == 3 {
                shop.garageModel = Equals(shop.garageModel, item.id) ? n"" : item.id;
                shop.garageStyle = n"";
            } else if item.kind == 4 {
                shop.garageModel = item.id2;
                shop.garageStyle = item.id;
            }
            return;
        }
        if tab == 4 {
            if item.kind >= -1 {
                shop.kitPart = item.kind;
            }
            return;
        }
        if tab == 5 || item.used {
            return;
        }
        if tab == 0 {
            shop.ChooseLook(item.id, item.main);
        } else if tab == 1 {
            let slots = this.PartSlots();
            if shop.slotIndex >= ArraySize(slots) {
                return;
            }
            let slot = slots[shop.slotIndex];
            if item.kind == 0 {
                shop.ClearSlot(slot);
            } else {
                shop.ChooseOption(slot, item.id, item.main);
            }
        } else if tab == 2 {
            if Equals(shop.wheelPart, n"rim") {
                shop.ChooseRims(item.id, item.main);
            } else {
                shop.ChooseTires(item.id, item.main);
            }
        } else if tab == 3 {
            let target = NameToString(shop.paintTarget);
            if Equals(target, "car") {
                shop.ChooseCarPaint(item.id);
            } else if Equals(target, "rim_f") {
                shop.ChooseRimPaint(n"f", item.id);
            } else if Equals(target, "rim_b") {
                shop.ChooseRimPaint(n"b", item.id);
            } else if item.kind == 0 {
                shop.ClearPartPaint(shop.paintTarget);
            } else {
                shop.ChoosePartPaint(shop.paintTarget, item.id);
            }
        }
    }

    private func ActLabel(id: CName) -> String {
        let shop = this.m_shop;
        let what = NameToString(id);
        if Equals(what, "ownsize") {
            return "Own size";
        }
        if Equals(what, "ownrimwidth") {
            return "Auto width";
        }
        if Equals(what, "fine") {
            return shop.fine ? "Fine steps" : "Big steps";
        }
        if Equals(what, "kit") {
            return this.m_actOn[0] ? "Take off" : "Fit";
        }
        if Equals(what, "resetplace") {
            return "Reset place";
        }
        if Equals(what, "buy") {
            return "Buy";
        }
        if Equals(what, "bring") {
            return "Bring here";
        }
        if Equals(what, "away") {
            return "Send away";
        }
        if Equals(what, "return") {
            return "Return it";
        }
        return what;
    }

    private func Act(id: CName) {
        let shop = this.m_shop;
        let what = NameToString(id);
        if Equals(what, "ownsize") {
            shop.ResetFit();
        } else if Equals(what, "ownrimwidth") {
            shop.SetRimWidth(100.0);
        } else if Equals(what, "fine") {
            shop.fine = !shop.fine;
        } else if Equals(what, "kit") {
            let kits = VCData.Names(this.m_cat, "kits");
            if shop.kitIndex < ArraySize(kits) {
                shop.ToggleKit(kits[shop.kitIndex], this.Code("kit." + NameToString(kits[shop.kitIndex])));
            }
        } else if Equals(what, "resetplace") {
            let kits = VCData.Names(this.m_cat, "kits");
            if shop.kitIndex < ArraySize(kits) {
                shop.ResetKitPlace(kits[shop.kitIndex], shop.kitPart);
            }
        } else if Equals(what, "buy") {
            shop.Buy(shop.garageModel, shop.garageStyle);
            shop.garagePick = n"mine";
            shop.garageStyle = n"";
            shop.garageCar = StringToName(TDBID.ToStringDEBUG(shop.Record()));
        } else if Equals(what, "bring") {
            shop.BringHere(TDBID.Create(NameToString(shop.garageCar)));
        } else if Equals(what, "away") {
            shop.SendAway(TDBID.Create(NameToString(shop.garageCar)));
        } else if Equals(what, "return") {
            shop.ReturnCar(TDBID.Create(NameToString(shop.garageCar)));
        }
    }

    // A stepper's minus or plus: wheel size and width, or a kit's place.
    private func Step(i: Int32, sign: Float) {
        let shop = this.m_shop;
        if shop.tab == 2 {
            let step = shop.fine ? 1.0 : 5.0;
            if Equals(shop.wheelPart, n"rim") {
                shop.StepRimWidth(sign * step);
            } else {
                shop.StepFit(i == 0 ? sign * step : 0.0, i == 1 ? sign * step : 0.0);
            }
        } else if shop.tab == 4 {
            let kits = VCData.Names(this.m_cat, "kits");
            if shop.kitIndex >= ArraySize(kits) {
                return;
            }
            let move = shop.fine ? 0.005 : 0.05;
            let turn = shop.fine ? 0.5 : 5.0;
            let m = new Vector4(i == 0 ? sign * move : 0.0, i == 1 ? sign * move : 0.0, i == 2 ? sign * move : 0.0,
                i == 3 ? sign * turn : 0.0);
            let t = new Vector4(i == 4 ? sign * turn : 0.0, i == 5 ? sign * turn : 0.0, 0.0, 0.0);
            shop.NudgeKit(kits[shop.kitIndex], shop.kitPart, m, t);
        }
    }

    private func View(i: Int32) {
        let shop = this.m_shop;
        if i == 6 || i == 7 {
            shop.viewExtra = ClampF(shop.viewExtra + (i == 6 ? -1.0 : 1.0), -3.0, 8.0);
            i = shop.lastView;
        }
        shop.lastView = i;
        let angles = [35.0, 0.0, 90.0, 145.0, 180.0, -90.0];
        let names = ["front three-quarter", "front", "side", "rear three-quarter", "rear", "other side"];
        shop.ViewFrom(angles[i], names[i]);
    }
}
