// Development only (vehicle-customizer/RECORD.md): lets an automated test run start without anyone at the PC.
// When the TweakDB flat VehicleCustomizerDev.autotest is true, which only tools/run-autotest.ps1 sets, for one
// run, the main menu does what its Continue button does as soon as it knows the newest save and the start screen
// ("press to continue", which only a key press closes; the run script taps Space) has gone, once per game launch.
// Continuing from under the start screen loaded the world with the start screen still drawn over it (the first
// suite runs, 2026-11-06: every picture showed it while the test ran). Without the flat it does nothing.
module VehicleCustomizerDev

public class AutoLoadState extends ScriptableService {
    public let done: Bool;
    // Kept here, not in the menu: closing the start screen opens the main menu anew, and the new one isn't told
    // about the saves again (fourth suite run: the menu showed and nothing pressed Continue).
    public let newestSaveKnown: Bool;
    public let newestSaveModded: Bool;
    public let startScreenOpen: Bool;
    public let startScreenClosed: Bool;
    public let menu: wref<SingleplayerMenuGameController>;
    public let tries: Int32;

    public func IsDone() -> Bool {
        return this.done;
    }

    // The CET runner asks again every few seconds, so nothing hangs on one menu event coming at the right time.
    public func Retry() {
        if !this.done && IsDefined(this.menu) {
            this.menu.VcdevTryAutoLoad();
        }
    }

    // The run script's word that the start screen has gone: in 2.5 neither the start screen's controller nor the
    // menu's switch away from it was seen (fifth suite run), while its taps had closed it by 45 s in every run.
    public func StartScreenGone() {
        this.startScreenOpen = false;
        this.startScreenClosed = true;
        this.Retry();
    }

    // For the run's report while it waits.
    public func Describe() -> String {
        return "start screen " + (this.startScreenOpen ? "open" : this.startScreenClosed ? "closed" : "not seen")
            + ", newest save " + (this.newestSaveKnown ? (this.newestSaveModded ? "known (modded)" : "known") : "not known")
            + ", menu " + (IsDefined(this.menu) ? "here" : "not here") + ", " + IntToString(this.tries) + " tries";
    }
}

// The main menu taking over from the start screen: the other sign it has gone.
@wrapMethod(MenuScenario_SingleplayerMenu)
protected cb func OnEnterScenario(prevScenario: CName, userData: ref<IScriptable>) -> Bool {
    let result = wrappedMethod(prevScenario, userData);
    let state = VcdevAutoLoadState();
    if IsDefined(state) && Equals(prevScenario, n"MenuScenario_EngagementScreen") {
        state.startScreenOpen = false;
        state.startScreenClosed = true;
        if IsDefined(state.menu) {
            state.menu.VcdevTryAutoLoad();
        }
    }
    return result;
}

func VcdevAutoLoadState() -> ref<AutoLoadState> {
    return GameInstance.GetScriptableServiceContainer().GetService(n"VehicleCustomizerDev.AutoLoadState") as AutoLoadState;
}

@wrapMethod(EngagementScreenGameController)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    let state = VcdevAutoLoadState();
    if IsDefined(state) {
        state.startScreenOpen = true;
    }
    return result;
}

@wrapMethod(EngagementScreenGameController)
protected cb func OnUninitialize() -> Bool {
    let result = wrappedMethod();
    let state = VcdevAutoLoadState();
    if IsDefined(state) {
        state.startScreenOpen = false;
        state.startScreenClosed = true;
        if IsDefined(state.menu) {
            state.menu.VcdevTryAutoLoad();
        }
    }
    return result;
}

@wrapMethod(SingleplayerMenuGameController)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    this.VcdevTryAutoLoad();
    return result;
}

@wrapMethod(SingleplayerMenuGameController)
protected cb func OnSavesForLoadReady(saves: array<String>) -> Bool {
    let result = wrappedMethod(saves);
    this.VcdevTryAutoLoad();
    return result;
}

@wrapMethod(SingleplayerMenuGameController)
protected cb func OnSaveMetadataReady(info: ref<SaveMetadataInfo>) -> Bool {
    let result = wrappedMethod(info);
    if info.saveIndex == 0 && info.isValid {
        let state = VcdevAutoLoadState();
        if IsDefined(state) {
            state.newestSaveKnown = true;
            state.newestSaveModded = info.isModded;
        }
        this.VcdevTryAutoLoad();
    }
    return result;
}

@addMethod(SingleplayerMenuGameController)
public func VcdevTryAutoLoad() {
    if !TweakDBInterface.GetBool(t"VehicleCustomizerDev.autotest", false) {
        return;
    }
    let state = VcdevAutoLoadState();
    if !IsDefined(state) || state.done {
        return;
    }
    state.menu = this;
    if !state.newestSaveKnown || state.startScreenOpen || !state.startScreenClosed {
        return;
    }
    // A menu made after the save's details came isn't told them again; Continue loads a modded save its own way.
    if state.newestSaveModded {
        this.m_isModded = true;
    }
    state.tries += 1;
    let data = new PauseMenuListItemData();
    data.action = PauseMenuAction.QuickLoad;
    if this.HandleMenuItemActivate(data) {
        state.done = true;
        FTLog("[VehicleCustomizerDev] autotest: continuing the newest save");
    }
}
