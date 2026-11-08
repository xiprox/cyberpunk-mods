// Development only (vehicle-customizer/RECORD.md): saving during an automated test run.
// While tools/run-autotest.ps1's flag is set (VehicleCustomizerDev.autotest), the game is told saving is locked,
// as it is during a chase or an autodrive, so neither an autosave nor anything else writes the playthrough's
// saves with a test's unlocked cars and builds in them. A job that tests saving lifts the lock only for its own
// quicksave (the user allowed quicksaves in the newest save's playthrough, 2026-11-06), made the way the
// quicksave key makes one, through the in-game menu's controller. Without the flag none of this does anything.
module VehicleCustomizerDev

public class NoSaveDuringTests extends ScriptableSystem {
    private func IsSavingLocked() -> Bool {
        let state = VcdevSaveState();
        return TweakDBInterface.GetBool(t"VehicleCustomizerDev.autotest", false) && !(IsDefined(state) && state.allowSaving);
    }

    public func IsLocked() -> Bool {
        return this.IsSavingLocked();
    }

    // Kept in the service, which lives as long as the game does, so a lift holds through loading a save (the
    // "prepare" job lifts it for good, to hand the game over to the user).
    public func Allow(allow: Bool) {
        let state = VcdevSaveState();
        if IsDefined(state) {
            state.allowSaving = allow;
        }
    }
}

// The in-game menu's controller, which makes quicksaves, and how the last one went.
public class SaveState extends ScriptableService {
    public let allowSaving: Bool;
    public let menu: wref<gameuiInGameMenuGameController>;
    public let asked: Int32;
    public let answers: Int32;
    public let lastOk: Bool;

    // Quicksaves now, as the quicksave key does; false if there is no in-game menu yet. The answer comes later.
    public func QuickSave() -> Bool {
        if !TweakDBInterface.GetBool(t"VehicleCustomizerDev.autotest", false) || !IsDefined(this.menu) {
            return false;
        }
        this.asked += 1;
        this.menu.VcdevQuickSave();
        return true;
    }

    // How many saves have finished since the game started, and whether the last one worked.
    public func Answers() -> Int32 {
        return this.answers;
    }

    public func LastOk() -> Bool {
        return this.lastOk;
    }
}

func VcdevSaveState() -> ref<SaveState> {
    return GameInstance.GetScriptableServiceContainer().GetService(n"VehicleCustomizerDev.SaveState") as SaveState;
}

@wrapMethod(gameuiInGameMenuGameController)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    let state = VcdevSaveState();
    if IsDefined(state) {
        state.menu = this;
    }
    return result;
}

@wrapMethod(gameuiInGameMenuGameController)
protected cb func OnSavingComplete(success: Bool, locks: array<gameSaveLock>) -> Bool {
    let result = wrappedMethod(success, locks);
    let state = VcdevSaveState();
    if IsDefined(state) {
        state.answers += 1;
        state.lastOk = success;
    }
    return result;
}

@addMethod(gameuiInGameMenuGameController)
public func VcdevQuickSave() {
    this.HandleQuickSave();
}
