// Vehicle Customizer: the paint tool's screen starting up (its menu is PaintTool.reds), and what both tools' screens share. The
// wrench's screen is built in Tool.reds.
module VehicleCustomizer

public abstract class VCToolScreens {
    public static func IsPaintTool(weapon: ref<WeaponObject>) -> Bool {
        return IsDefined(weapon) && ItemID.GetTDBID(weapon.GetItemID()) == t"Items.VC_PaintTool";
    }

    // The gun screen's own content hidden; the menu goes on from the tool's tick, as the wrench's does, once the widget is up.
    public static func BuildPaint(game: GameInstance, root: ref<inkCompoundWidget>, weapon: wref<WeaponObject>) {
        if !IsDefined(root) {
            return;
        }
        let i = 0;
        while i < root.GetNumChildren() {
            root.GetWidget(i).SetVisible(false);
            i += 1;
        }
        VCPaintTool.Get(game).TakeScreen(root, weapon);
    }

    // The screen and its case keep their size on the player's screen at any field of view (user, 2026-11-08): a thing's size on
    // screen goes with 1 / (distance * tan(fov / 2)), so they move along the tool, nearer the eye as the view widens. 0.292 m
    // is the screen's distance from the eye at the default 80 (RECORD.md). Only this player's own tool moves: a partner's copy
    // in this game stays as built, since the fit is for the eye of whoever holds it.
    public static func FitToFov(game: GameInstance, weapon: ref<WeaponObject>) {
        if !IsDefined(weapon) || weapon.GetOwner() != GetPlayer(game) {
            return;
        }
        let setting = GameInstance.GetSettingsSystem(game).GetVar(n"/graphics/basic", n"FieldOfView") as ConfigVarFloat;
        let fov = IsDefined(setting) ? setting.GetValue() : 80.0;
        let want = 0.292 * (TanF(Deg2Rad(40.0)) / TanF(Deg2Rad(fov * 0.5)) - 1.0);
        want = MaxF(-0.12, MinF(0.10, want));
        for component in weapon.GetComponents() {
            let part = component as MeshComponent;
            if IsDefined(part) && (Equals(part.name, n"vc_tool_screen") || Equals(part.name, n"vc_tool_housing")) {
                let p = part.GetLocalPosition();
                if AbsF(p.Y - want) > 0.0005 {
                    part.SetLocalPosition(new Vector4(p.X, want, p.Z, p.W));
                }
            }
        }
    }
}

@wrapMethod(IronsightGameController)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    let weapon = this.GetOwnerEntity() as WeaponObject;
    if VCToolScreens.IsPaintTool(weapon) {
        VCToolScreens.BuildPaint(weapon.GetGame(), this.GetRootCompoundWidget(), weapon);
    }
    if VCToolScreens.IsPaintTool(weapon) || VCTool.IsTool(weapon) {
        VCToolScreens.FitToFov(weapon.GetGame(), weapon);
    }
    return result;
}
