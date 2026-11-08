// Development only (vehicle-customizer/RECORD.md, job "toolkeys", 2026-11-08): whether the mouse buttons and R reach
// Codeware's Input/Key callback with the tool in hand, and what the player's state machine does meanwhile. The paint
// tool's left and right click depend on the first; the tool's wraps (Tool.reds) on the second.
module VehicleCustomizerDev

public class ProbeKeys extends ScriptableSystem {
    private let m_left: Int32;
    private let m_right: Int32;
    private let m_r: Int32;

    private func OnAttach() {
        GameInstance.GetCallbackSystem().RegisterCallback(n"Input/Key", this, n"OnKey");
    }

    private func OnDetach() {
        GameInstance.GetCallbackSystem().UnregisterCallback(n"Input/Key", this);
    }

    private cb func OnKey(event: ref<KeyInputEvent>) {
        if !Equals(event.GetAction(), EInputAction.IACT_Press) {
            return;
        }
        switch event.GetKey() {
            case EInputKey.IK_LeftMouse: this.m_left += 1; break;
            case EInputKey.IK_RightMouse: this.m_right += 1; break;
            case EInputKey.IK_R: this.m_r += 1; break;
        }
    }

    public func Left() -> Int32 {
        return this.m_left;
    }

    public func Right() -> Int32 {
        return this.m_right;
    }

    public func R() -> Int32 {
        return this.m_r;
    }

    private func Board() -> ref<IBlackboard> {
        let player = GetPlayer(this.GetGameInstance());
        return player.GetPlayerStateMachineBlackboard();
    }

    // gamePSMUpperBodyStates: 6 is Aim.
    public func UpperBody() -> Int32 {
        return this.Board().GetInt(GetAllBlackboardDefs().PlayerStateMachine.UpperBody);
    }

    // gamePSMRangedWeaponStates: 2 is Reload, 6 is Safe (public safe too), 8 is Shoot.
    public func RightWeapon() -> Int32 {
        return this.Board().GetInt(GetAllBlackboardDefs().PlayerStateMachine.RightWeapon);
    }

    // gamePSMZones: 1 is Public, 2 is Safe.
    public func Zone() -> Int32 {
        return this.Board().GetInt(GetAllBlackboardDefs().PlayerStateMachine.Zones);
    }

    public func ToolCount() -> Int32 {
        let game = this.GetGameInstance();
        let items: array<wref<gameItemData>>;
        GameInstance.GetTransactionSystem(game).GetItemList(GetPlayer(game), items);
        let count = 0;
        for item in items {
            if ItemID.GetTDBID(item.GetID()) == t"Items.VC_Tool" {
                count += item.GetQuantity();
            }
        }
        return count;
    }
}
