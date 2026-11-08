// Development only (vehicle-customizer/RECORD.md, tool probes of 2026-11-07): the tool, a copy of the turret gun
// (Items.VC_ProbeTool, dev/r6/tweaks/vehiclecustomizerdev/probe-tool.yaml), never fires. The weapon's state
// machine asks WeaponTransition.ShouldShoot before every kind of shot (semi-auto, full-auto, burst, charge), so
// the answer is no while the tool is in V's hand, and the fire button stays free for the tool's own use. Frames
// with fire held and the shot refused are counted for the probe job (Lua reads ProbeToolGuard.Refused).
module VehicleCustomizerDev

public class ProbeToolGuard extends ScriptableSystem {
    private let m_refused: Int32;
    // Probe 4: our own text on the gun's screen (the Mk.31's ammo counter, militech_hmg.inkwidget, painted on
    // its ammo-counter mesh), set by the probe job to the part under the crosshair.
    public let screenText: wref<inkText>;

    // Every time the weapon's state machine asked about a shot with the tool in hand, fire held or not: the first
    // tool run counted no refusals, which alone can't tell "fire never held" from "never asked".
    private let m_asked: Int32;

    public func Refused() -> Int32 {
        return this.m_refused;
    }

    public func Asked() -> Int32 {
        return this.m_asked;
    }

    public func CountAsked() {
        this.m_asked += 1;
    }

    public func CountRefusal() {
        this.m_refused += 1;
    }

    public func HasScreen() -> Bool {
        return IsDefined(this.screenText);
    }

    public func SetScreenText(text: String) {
        if IsDefined(this.screenText) {
            this.screenText.SetText(text);
        }
    }
}

// The turret gun's screen runs IronsightGameController (ironsight.script), which many guns share, so only the
// tool's is touched: its ammo count ("main") is hidden and a text of ours takes its place.
@wrapMethod(IronsightGameController)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    let weapon = this.GetOwnerEntity() as WeaponObject;
    if VcdevIsProbeTool(weapon) {
        let root = this.GetRootCompoundWidget();
        let main = root.GetWidget(n"main");
        let text = new inkText();
        text.SetName(n"vcdev_screen");
        text.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        text.SetFontStyle(n"Semi-Bold");
        text.SetFontSize(72);
        text.SetLetterCase(textLetterCase.UpperCase);
        text.SetTintColor(new HDRColor(0.45, 1.0, 0.65, 1.0));
        text.SetHorizontalAlignment(textHorizontalAlignment.Center);
        text.SetVerticalAlignment(textVerticalAlignment.Center);
        text.SetText("aim at a part");
        if IsDefined(main) {
            text.SetAnchor(main.GetAnchor());
            text.SetAnchorPoint(main.GetAnchorPoint());
            text.SetMargin(main.GetMargin());
            text.SetSize(main.GetSize());
            main.SetVisible(false);
        } else {
            text.SetSize(512.0, 242.0);
        }
        text.Reparent(root);
        let game = weapon.GetGame();
        let guard = GameInstance.GetScriptableSystemsContainer(game).Get(n"VehicleCustomizerDev.ProbeToolGuard") as ProbeToolGuard;
        if IsDefined(guard) {
            guard.screenText = text;
        }
    }
    return result;
}

public func VcdevIsProbeTool(weapon: ref<WeaponObject>) -> Bool {
    return IsDefined(weapon) && Equals(ItemID.GetTDBID(weapon.GetItemID()), t"Items.VC_ProbeTool");
}

@wrapMethod(WeaponTransition)
protected const func ShouldShoot(scriptInterface: ref<StateGameScriptInterface>) -> Bool {
    let weapon = this.GetWeaponObject(scriptInterface);
    if VcdevIsProbeTool(weapon) {
        let game = scriptInterface.executionOwner.GetGame();
        let guard = GameInstance.GetScriptableSystemsContainer(game).Get(n"VehicleCustomizerDev.ProbeToolGuard") as ProbeToolGuard;
        if IsDefined(guard) {
            guard.CountAsked();
            if scriptInterface.GetActionValue(n"RangedAttack") > 0.0 {
                guard.CountRefusal();
            }
        }
        return false;
    }
    return wrappedMethod(scriptInterface);
}
