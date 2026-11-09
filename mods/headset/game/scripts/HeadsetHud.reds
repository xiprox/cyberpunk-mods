// The small headphones and the mode's name on the HUD, under the health bar, whenever the headset is doing something. Hidden in Passthrough.
// In the HUD layer, so it fades with the rest of the HUD in menus. Top level, as HeadsetNative is: CET calls Tick by the plain name.
public class HeadsetHud extends ScriptableService {
    private let m_root: wref<inkCanvas>;
    private let m_icon: wref<inkImage>;
    private let m_text: wref<inkText>;
    private let m_shown: Int32;

    public static func Tick() -> Void {
        let hud = GameInstance.GetScriptableServiceContainer().GetService(n"HeadsetHud") as HeadsetHud;
        if IsDefined(hud) {
            hud.Update();
        }
    }

    // Every frame, but it only touches the widgets when the mode changes. A load takes the HUD and our widgets with it, so they're built again.
    private func Update() {
        if !IsDefined(this.m_root) && !this.Build() {
            return;
        }
        let mode = HeadsetNative.EffectiveMode();
        if mode == this.m_shown {
            return;
        }
        this.m_shown = mode;
        this.m_root.SetVisible(mode != 0);
        let color = HDRColor(0.368627, 0.964706, 1.0, 1.0);
        this.m_icon.SetTintColor(color);
        this.m_text.SetTintColor(color);
        this.m_text.SetText(mode == 1 ? "Hearing Protection" : "Noise Cancelling");
    }

    private func Build() -> Bool {
        let layer = GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer");
        if !IsDefined(layer) {
            return false;
        }
        let window = layer.GetVirtualWindow();
        if !IsDefined(window) {
            return false;
        }

        let root = new inkCanvas();
        root.SetName(n"HeadsetHud");
        root.SetAnchor(inkEAnchor.TopLeft);
        // The HUD layer is about one unit to a screen pixel, unlike a popup's two. Lined up with NightCoop Voice's display, just above it.
        root.SetMargin(inkMargin(70.0, 206.0, 0.0, 0.0));
        root.SetFitToContent(true);
        root.Reparent(window);
        this.m_root = root;

        let row = new inkHorizontalPanel();
        row.SetFitToContent(true);
        row.Reparent(root);

        let icon = new inkImage();
        icon.SetAtlasResource(r"headset\\wheel\\wheel.inkatlas");
        icon.SetTexturePart(n"headphones");
        icon.SetSize(Vector2(24.0, 24.0));
        icon.SetVAlign(inkEVerticalAlign.Center);
        icon.Reparent(row);
        this.m_icon = icon;

        let text = new inkText();
        text.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        text.SetFontStyle(n"Medium");
        text.SetFontSize(24); // as NightCoop Voice's rows, and like them not in capitals
        text.SetFitToContent(true);
        text.SetVAlign(inkEVerticalAlign.Center);
        text.SetMargin(inkMargin(6.0, 0.0, 0.0, 0.0));
        text.Reparent(row);
        this.m_text = text;

        this.m_shown = -1;
        return true;
    }
}
