// Vehicle Customizer: what keeps the tools from acting like guns, where no weapon record can (RECORD.md, 2026-11-08; user: not
// scare citizens, no idle animations, no melee, no wrong HUD). Both tools, wrench and paint.
module VehicleCustomizer

public abstract class VCToolRules {
    public static func IsAnyId(id: ItemID) -> Bool {
        let record = ItemID.GetTDBID(id);
        return record == t"Items.VC_Tool" || record == t"Items.VC_PaintTool";
    }

    public static func IsAny(weapon: ref<WeaponObject>) -> Bool {
        return IsDefined(weapon) && VCToolRules.IsAnyId(weapon.GetItemID());
    }
}

// No quick melee: all three ways into it ask this first (weaponTransitions.script).
@wrapMethod(WeaponTransition)
protected const func CanQuickMelee(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Bool {
    if VCToolRules.IsAny(this.GetWeaponObject(scriptInterface)) {
        return false;
    }
    return wrappedMethod(stateContext, scriptInterface);
}

// No idle break: the game plays one once this timestamp is 20 s old, so it's kept fresh (ReadyEvents.OnTick).
@wrapMethod(ReadyEvents)
protected func OnTick(timeDelta: Float, stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) {
    if VCToolRules.IsAny(this.GetWeaponObject(scriptInterface)) {
        this.m_timeStamp = EngineTime.ToFloat(GameInstance.GetSimTime(scriptInterface.GetGame()));
    }
    wrappedMethod(timeDelta, stateContext, scriptInterface);
}

// Citizens don't react: the game announces any weapon but fists when it's drawn, on the first draw here and otherwise
// on reaching Equipped (equipment.script). The first draw has nothing else in it; the flag makes Equipped skip its own.
@wrapMethod(FirstEquipEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) {
    if VCToolRules.IsAny(GameObject.GetActiveWeapon(scriptInterface.executionOwner)) {
        stateContext.SetPermanentBoolParameter(n"weaponDisplayedStimuli", true, true);
        return;
    }
    wrappedMethod(stateContext, scriptInterface);
}

@wrapMethod(EquippedEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) {
    if VCToolRules.IsAny(GameObject.GetActiveWeapon(scriptInterface.executionOwner)) {
        stateContext.SetPermanentBoolParameter(n"weaponDisplayedStimuli", true, true);
    }
    wrappedMethod(stateContext, scriptInterface);
}

// The corner panel with the weapon's name and ammo doesn't show for a tool.
@wrapMethod(WeaponRosterGameController)
protected cb func OnWeaponDataChanged(value: Variant) -> Bool {
    let result = wrappedMethod(value);
    let data = FromVariant<ref<SlotDataHolder>>(value);
    if IsDefined(data) {
        this.GetRootWidget().SetVisible(!VCToolRules.IsAnyId(data.rightWeapon.weaponID));
    }
    return result;
}
