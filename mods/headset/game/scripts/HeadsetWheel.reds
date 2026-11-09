// The headset's mode wheel: hold the headset key, move the mouse, let go. Three equal slices: Active Noise Cancellation top left,
// Active Hearing Protection top right, Passthrough at the bottom. Opened and closed from game/cet, when the plugin says the key is held
// and let go. Drawn like the game's own wheel. The art is ours (tools/make_wheel_art.py): the game ignored inkShape vertex lists.
// Top level, as HeadsetNative is: CET finds these classes by their plain names.
import Codeware.UI.*

public class HeadsetWheel extends InGamePopup {
    private let m_showing: Bool;
    private let m_closeWhenShown: Bool;
    private let m_flipY: Bool;
    private let m_x: Float;
    private let m_y: Float;
    private let m_current: Int32;
    private let m_choice: Int32;
    // All by mode: 0 Passthrough, 1 Hearing Protection, 2 Noise Cancelling.
    private let m_glows: array<ref<inkImage>>;
    private let m_lines: array<ref<inkImage>>;
    private let m_rims: array<ref<inkImage>>;
    private let m_waves: array<ref<inkImage>>;
    // One text per line, so that each is centred on its own; the mode each belongs to is beside it.
    private let m_labelLines: array<ref<inkText>>;
    private let m_labelModes: array<Int32>;
    private let m_pointer: ref<inkImage>;
    private let m_dot: ref<inkCircle>;
    private let m_title: ref<inkText>;
    private let m_body: ref<inkText>;
    private let m_surroundings: ref<inkText>;
    private let m_gunfire: ref<inkText>;
    private let m_phoneHint: wref<inkWidget>;
    private let m_phoneHintOpacity: Float;

    // No cursor: the mouse's raw movement says which way you're pointing, as the game's own wheel does.
    public func UseCursor() -> Bool {
        return false;
    }

    // The queue the vehicle customizer settled on: Codeware's own left the world behind a popup black or frozen.
    public func GetQueueName() -> CName {
        return n"VehicleVisualCustomization";
    }

    // The game's wheel: a faint black layer, with the red vignette over it.
    protected func CreateVignette() {
        let dim = new inkRectangle();
        dim.SetAnchor(inkEAnchor.Fill);
        dim.SetTintColor(HDRColor(0.0, 0.0, 0.0, 1.0));
        dim.SetOpacity(0.15);
        dim.Reparent(this.GetRootCompoundWidget());
        super.CreateVignette();
    }

    protected func CreateContainer() {
        let container = new inkCanvas();
        container.SetName(n"container");
        container.SetAnchor(inkEAnchor.Fill);
        container.Reparent(this.GetRootCompoundWidget());
        this.m_container = container;
        this.SetContainerWidget(container);
    }

    protected cb func OnCreate() {
        super.OnCreate();
        this.m_current = HeadsetNative.ChosenMode();
        this.m_choice = -1;
        this.m_flipY = HeadsetNative.WheelFlipY();
        this.Build();
    }

    protected cb func OnInitialize() {
        super.OnInitialize();
        this.RegisterToGlobalInputCallback(n"OnPostOnRelative", this, n"OnMouse");
        this.RegisterToGlobalInputCallback(n"OnPostOnAxis", this, n"OnMouse");
    }

    // At once, not with the popup's half-second fade: a wheel you hold for a moment has to be there when you want it.
    // The blur stays on, as it does on the game's wheel and the vehicle customizer's popup: without asking for it, what's behind a popup
    // is a still frame from the last time one was open. Closing clears it (InGamePopup.OnHide).
    protected cb func OnShow() {
        this.SetUIContext();
        this.SetTimeDilation();
        PopupStateUtils.SetBackgroundBlurBlendTime(this.GetGameController(), 0.1);
        this.SetBackgroundBlur();
        this.HidePhoneHint();
        this.m_showing = true;
        if this.m_closeWhenShown {
            this.Close();
        }
    }

    // The modal state hides most of the HUD but not the phone's corner. Only its opacity changes, put back exactly as it was on closing,
    // and no game function is replaced, so a UI mod that moves or restyles it is left alone; if the phone HUD isn't there, nothing happens.
    private func HidePhoneHint() {
        let layer = GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer");
        if !IsDefined(layer) {
            return;
        }
        let controllers = layer.GetGameControllers();
        let i = 0;
        while i < ArraySize(controllers) {
            if controllers[i].IsA(n"NewHudPhoneGameController") {
                let root = controllers[i].GetRootWidget();
                if IsDefined(root) {
                    this.m_phoneHint = root;
                    this.m_phoneHintOpacity = root.GetOpacity();
                    root.SetOpacity(0.0);
                }
                return;
            }
            i += 1;
        }
    }

    private func RestorePhoneHint() {
        if IsDefined(this.m_phoneHint) {
            this.m_phoneHint.SetOpacity(this.m_phoneHintOpacity);
            this.m_phoneHint = null;
        }
    }

    protected cb func OnHide() {
        this.RestorePhoneHint();
        this.m_showing = false;
        this.UnregisterFromGlobalInputCallback(n"OnPostOnRelative", this, n"OnMouse");
        this.UnregisterFromGlobalInputCallback(n"OnPostOnAxis", this, n"OnMouse");
        HeadsetWheelHost.Get().Closed(this);
        super.OnHide();
    }

    // The headset key was let go: what you were pointing at, if you pointed at anything, is the new mode.
    public func Release() {
        if !this.m_showing {
            this.m_closeWhenShown = true;
            HeadsetWheelHost.Get().Closed(this);
            return;
        }
        if this.m_choice >= 0 {
            HeadsetNative.ChooseMode(this.m_choice);
        }
        this.Close();
    }

    protected cb func OnMouse(evt: ref<inkPointerEvent>) -> Bool {
        if !this.m_showing {
            return false;
        }
        if evt.IsAction(n"mouse_x") {
            this.m_x += evt.GetAxisData();
        } else if evt.IsAction(n"mouse_y") {
            this.m_y += this.m_flipY ? -evt.GetAxisData() : evt.GetAxisData();
        } else {
            return false;
        }

        // Kept to a short reach, so that changing your mind takes a small move, whichever way you went first.
        let reach = SqrtF(this.m_x * this.m_x + this.m_y * this.m_y);
        if reach > 200.0 {
            this.m_x *= 200.0 / reach;
            this.m_y *= 200.0 / reach;
            reach = 200.0;
        }
        if reach < 30.0 {
            return false;
        }

        // Degrees clockwise from straight up.
        let angle = Rad2Deg(AtanF(this.m_x, this.m_y));
        if angle < 0.0 {
            angle += 360.0;
        }
        this.m_pointer.SetRotation(angle);
        let picked = angle < 120.0 ? 1 : angle < 240.0 ? 0 : 2;
        if picked != this.m_choice {
            this.m_choice = picked;
            this.Paint();
            GameInstance.GetAudioSystem(GetGameInstance()).Play(n"ui_menu_hover");
        }
        return false;
    }

    // The canvas is wide enough for the wheel and the panel beside it, with the wheel in the middle of the screen, at (1400, 680).
    // The art is a square 1280 across (tools/make_wheel_art.py has the same numbers); slices reach 540 from the centre, from a hub of 104.
    private func Build() {
        let wheel = new inkCanvas();
        wheel.SetAnchor(inkEAnchor.Centered);
        wheel.SetAnchorPoint(Vector2(0.5, 0.5));
        wheel.SetSize(Vector2(2800.0, 1360.0));
        wheel.Reparent(this.GetContainerWidget());

        ArrayResize(this.m_glows, 3);
        ArrayResize(this.m_lines, 3);
        ArrayResize(this.m_rims, 3);
        ArrayResize(this.m_waves, 3);

        let ring = this.AddArt(wheel, n"ring", 0.0);
        ring.SetTintColor(HeadsetWheel.Red());
        ring.SetOpacity(0.55);

        // The art is the slice from straight up to 120 degrees clockwise, turned into place.
        this.AddSlice(wheel, 1, 0.0);
        this.AddSlice(wheel, 0, 120.0);
        this.AddSlice(wheel, 2, 240.0);

        this.AddDisc(wheel, 164.0, HeadsetWheel.Red(), 0.8);
        this.AddDisc(wheel, 160.0, HeadsetWheel.Dark(), 1.0);
        this.m_dot = this.AddDisc(wheel, 20.0, HeadsetWheel.Red(), 1.0);

        this.AddContent(wheel, 1, 60.0, "Active Hearing", "Protection");
        this.AddContent(wheel, 0, 180.0, "Passthrough", "");
        this.AddContent(wheel, 2, 300.0, "Active Noise", "Cancellation");

        this.m_pointer = this.AddArt(wheel, n"pointer", 0.0);
        this.m_pointer.SetTintColor(HeadsetWheel.Blue());

        this.BuildPanel(wheel);
        this.Paint();
    }

    private func AddSlice(parent: ref<inkCompoundWidget>, mode: Int32, rotation: Float) {
        let dark = this.AddArt(parent, n"fill", rotation);
        dark.SetTintColor(HeadsetWheel.Dark());
        dark.SetOpacity(0.62);
        let glow = this.AddArt(parent, n"glow", rotation);
        glow.SetTintColor(HeadsetWheel.Blue());
        this.m_glows[mode] = glow;
        this.m_lines[mode] = this.AddArt(parent, n"line", rotation);
        let rim = this.AddArt(parent, n"rim", rotation);
        rim.SetTintColor(HeadsetWheel.Blue());
        this.m_rims[mode] = rim;
    }

    private func AddArt(parent: ref<inkCompoundWidget>, part: CName, rotation: Float) -> ref<inkImage> {
        let image = this.MakeImage(parent, part, 760.0, 40.0, 1280.0, 1280.0);
        image.SetRenderTransformPivot(Vector2(0.5, 0.5));
        image.SetRotation(rotation);
        return image;
    }

    private func MakeImage(parent: ref<inkCompoundWidget>, part: CName, x: Float, y: Float, w: Float, h: Float) -> ref<inkImage> {
        let image = new inkImage();
        image.SetAtlasResource(r"headset\\wheel\\wheel.inkatlas");
        image.SetTexturePart(part);
        image.SetAnchor(inkEAnchor.TopLeft);
        image.SetMargin(inkMargin(x, y, 0.0, 0.0));
        image.SetSize(Vector2(w, h));
        image.Reparent(parent);
        return image;
    }

    private func AddDisc(parent: ref<inkCompoundWidget>, size: Float, color: HDRColor, opacity: Float) -> ref<inkCircle> {
        let disc = new inkCircle();
        disc.SetAnchor(inkEAnchor.TopLeft);
        disc.SetAnchorPoint(Vector2(0.5, 0.5));
        disc.SetMargin(inkMargin(1400.0, 680.0, 0.0, 0.0));
        disc.SetSize(Vector2(size, size));
        disc.SetTintColor(color);
        disc.SetOpacity(opacity);
        disc.Reparent(parent);
        return disc;
    }

    // The icon, name and Active tag stacked, the stack as a whole centred on the slice's centre of area, which is 307 from the wheel's centre.
    private func AddContent(parent: ref<inkCompoundWidget>, mode: Int32, angle: Float, first: String, second: String) {
        let x = 1400.0 + 307.0 * SinF(Deg2Rad(angle));
        let y = 680.0 - 307.0 * CosF(Deg2Rad(angle));
        let lines = Equals(second, "") ? 1.0 : 2.0;
        let active = mode == this.m_current;
        let top = y - (66.0 + 14.0 + 50.0 * lines + (active ? 42.0 : 0.0)) / 2.0;

        let part = mode == 1 ? n"wave1" : mode == 2 ? n"wave2" : n"wave0";
        let wave = this.MakeImage(parent, part, x - 66.0, top, 132.0, 66.0);
        this.m_waves[mode] = wave;

        this.AddLabelLine(parent, mode, first, x, top + 105.0);
        if lines > 1.0 {
            this.AddLabelLine(parent, mode, second, x, top + 155.0);
        }
        if active {
            let tag = this.AddText(parent, "Active", 30, x, top + 80.0 + 50.0 * lines + 24.0, 0.5, 0.5, true);
            tag.SetTintColor(HeadsetWheel.Red());
        }
    }

    private func AddLabelLine(parent: ref<inkCompoundWidget>, mode: Int32, content: String, x: Float, y: Float) {
        ArrayPush(this.m_labelLines, this.AddText(parent, content, 42, x, y, 0.5, 0.5, true));
        ArrayPush(this.m_labelModes, mode);
    }

    private func AddText(parent: ref<inkCompoundWidget>, content: String, size: Int32, x: Float, y: Float, anchorX: Float, anchorY: Float, capitals: Bool) -> ref<inkText> {
        let text = new inkText();
        text.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        text.SetFontStyle(n"Medium");
        text.SetFontSize(size);
        if capitals {
            text.SetLetterCase(textLetterCase.UpperCase);
        }
        text.SetAnchor(inkEAnchor.TopLeft);
        text.SetAnchorPoint(Vector2(anchorX, anchorY));
        text.SetMargin(inkMargin(x, y, 0.0, 0.0));
        text.SetFitToContent(true);
        text.SetTintColor(HeadsetWheel.White());
        text.SetText(content);
        text.Reparent(parent);
        return text;
    }

    // Beside the wheel, like the game's item panel: what the mode you're pointing at does.
    private func BuildPanel(parent: ref<inkCompoundWidget>) {
        let x = 2064.0;
        let y = 400.0;
        let w = 620.0;
        let h = 560.0;
        let fill = this.MakeImage(parent, n"panel_fill", x, y, w, h);
        fill.SetTintColor(HeadsetWheel.Dark());
        fill.SetOpacity(0.93);
        let outline = this.MakeImage(parent, n"panel_line", x, y, w, h);
        outline.SetTintColor(HeadsetWheel.Red());
        outline.SetOpacity(0.8);
        this.AddBox(parent, x, y, 8.0, h, HeadsetWheel.Red(), 1.0);

        let left = x + 48.0;
        let right = x + w - 48.0;
        this.m_title = this.AddText(parent, "", 44, left, y + 36.0, 0.0, 0.0, true);
        this.m_title.SetTintColor(HeadsetWheel.Blue());
        let kind = this.AddText(parent, "Headset mode", 30, left, y + 150.0, 0.0, 0.0, false);
        kind.SetTintColor(HeadsetWheel.Red());
        this.m_body = this.AddText(parent, "", 34, left, y + 212.0, 0.0, 0.0, false);

        this.AddBox(parent, left, y + 412.0, right - left, 2.0, HeadsetWheel.Red(), 0.5);
        this.AddText(parent, "Surroundings", 32, left, y + 432.0, 0.0, 0.0, false);
        this.AddText(parent, "Gunfire", 32, left, y + 482.0, 0.0, 0.0, false);
        this.m_surroundings = this.AddText(parent, "", 32, right, y + 432.0, 1.0, 0.0, false);
        this.m_surroundings.SetTintColor(HeadsetWheel.Blue());
        this.m_gunfire = this.AddText(parent, "", 32, right, y + 482.0, 1.0, 0.0, false);
        this.m_gunfire.SetTintColor(HeadsetWheel.Blue());
    }

    private func AddBox(parent: ref<inkCompoundWidget>, x: Float, y: Float, w: Float, h: Float, color: HDRColor, opacity: Float) {
        let box = new inkRectangle();
        box.SetAnchor(inkEAnchor.TopLeft);
        box.SetMargin(inkMargin(x, y, 0.0, 0.0));
        box.SetSize(Vector2(w, h));
        box.SetTintColor(color);
        box.SetOpacity(opacity);
        box.Reparent(parent);
    }

    // What you're pointing at is lit. Before you've pointed at anything, the mode you're in is.
    private func Paint() {
        let lit = this.m_choice >= 0 ? this.m_choice : this.m_current;
        let mode = 0;
        while mode < 3 {
            let on = mode == lit;
            this.m_glows[mode].SetOpacity(on ? 0.22 : 0.0);
            this.m_lines[mode].SetTintColor(on ? HeadsetWheel.Blue() : HeadsetWheel.Red());
            this.m_lines[mode].SetOpacity(on ? 1.0 : 0.75);
            this.m_rims[mode].SetVisible(on);
            this.m_waves[mode].SetTintColor(on ? HeadsetWheel.Blue() : HeadsetWheel.White());
            this.m_waves[mode].SetOpacity(on ? 0.8 : 0.45);
            mode += 1;
        }
        let i = 0;
        while i < ArraySize(this.m_labelLines) {
            this.m_labelLines[i].SetTintColor(this.m_labelModes[i] == lit ? HeadsetWheel.Blue() : HeadsetWheel.White());
            i += 1;
        }
        this.m_dot.SetTintColor(this.m_choice >= 0 ? HeadsetWheel.Blue() : HeadsetWheel.Red());
        this.m_pointer.SetVisible(this.m_choice >= 0);
        this.m_title.SetText(HeadsetWheel.Title(lit));
        this.m_body.SetText(HeadsetWheel.Body(lit));
        this.m_surroundings.SetText(HeadsetWheel.Surroundings(lit));
        this.m_gunfire.SetText(HeadsetWheel.Gunfire(lit));
    }

    private static func Title(mode: Int32) -> String {
        if mode == 1 {
            return "Active Hearing\nProtection";
        }
        if mode == 2 {
            return "Active Noise\nCancellation";
        }
        return "Passthrough";
    }

    private static func Body(mode: Int32) -> String {
        if mode == 1 {
            return "Ear-cup mics keep you aware\nof your surroundings, and\nclamp down the instant a\ngun or blast goes off.";
        }
        if mode == 2 {
            return "Silences the city around\nyou, a car's radio too.\nIt can't keep up with\ngunfire.";
        }
        return "No processing. You hear\nthe city exactly as it is.";
    }

    private static func Surroundings(mode: Int32) -> String {
        if mode == 1 {
            return "Through mics";
        }
        if mode == 2 {
            return "Silenced";
        }
        return "Unfiltered";
    }

    private static func Gunfire(mode: Int32) -> String {
        if mode == 1 {
            return "Clamped";
        }
        if mode == 2 {
            return "Still hits hard";
        }
        return "Full force";
    }

    // The game's own colours, from its main colour style.
    public static func Red() -> HDRColor {
        return HDRColor(1.1761, 0.3809, 0.3476, 1.0);
    }

    public static func Blue() -> HDRColor {
        return HDRColor(0.368627, 0.964706, 1.0, 1.0);
    }

    public static func Dark() -> HDRColor {
        return HDRColor(0.054902, 0.054902, 0.090196, 1.0);
    }

    public static func White() -> HDRColor {
        return HDRColor(0.92, 0.93, 0.95, 1.0);
    }
}

// Keeps the open wheel between the key being held and let go.
public class HeadsetWheelHost extends ScriptableService {
    private let m_wheel: ref<HeadsetWheel>;

    public static func Get() -> ref<HeadsetWheelHost> {
        return GameInstance.GetScriptableServiceContainer().GetService(n"HeadsetWheelHost") as HeadsetWheelHost;
    }

    public static func Open() -> Void {
        HeadsetWheelHost.Get().OpenWheel();
    }

    public static func Close() -> Void {
        HeadsetWheelHost.Get().ReleaseWheel();
    }

    public func OpenWheel() {
        if IsDefined(this.m_wheel) {
            return;
        }
        let manager = CustomPopupManager.GetInstance();
        if !IsDefined(manager) || !manager.IsInitialized() {
            return;
        }
        let wheel = new HeadsetWheel();
        this.m_wheel = wheel;
        manager.ShowPopup(wheel);
    }

    public func ReleaseWheel() {
        if IsDefined(this.m_wheel) {
            this.m_wheel.Release();
        }
    }

    public func Closed(wheel: ref<HeadsetWheel>) {
        if Equals(this.m_wheel, wheel) {
            this.m_wheel = null;
        }
    }
}
