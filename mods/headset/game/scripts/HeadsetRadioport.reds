// With "Radioport puts the headset on" switched on, turning the Radioport on in Passthrough switches to the mode chosen for it in the
// menu, and turning it off goes back to Passthrough if the Radioport was what took the headset out of it. The headset never works the
// Radioport.
//
// Only what the player does to the Radioport counts: the game also turns it off and on by itself, for calls, scenes, clubs and fast
// travel (pocketRadio.script), and following those would take the headset off for every call. So each way a player works it notes
// its state as the action starts, and the next frames show whether it went on or off.
// The note is taken where the action starts, not where the Radioport handles it, because AudioWare Radio Framework starts a station of
// its own inside SendRadioEvent and only then tells the player (its RadioEvents.reds), so by the player's own handler it's already on.
// Nothing here depends on that mod: it changes what IsActive says, and this reads IsActive.
// Top level, as HeadsetNative is: CET calls Tick by the plain name.
public class HeadsetRadioport extends ScriptableService {
    private let m_watching: Bool; // a player's action on the Radioport hasn't settled yet
    private let m_wasOn: Bool;    // the Radioport as that action started
    private let m_seen: Bool;     // as last seen
    private let m_seenAt: Float;  // when it last changed, or the player last acted, in engine time
    private let m_putOn: Bool;    // turning the Radioport on took the headset out of Passthrough

    public static func Get() -> ref<HeadsetRadioport> {
        return GameInstance.GetScriptableServiceContainer().GetService(n"HeadsetRadioport") as HeadsetRadioport;
    }

    // Every frame, from game/cet.
    public static func Tick() -> Void {
        let service = HeadsetRadioport.Get();
        if IsDefined(service) {
            service.Update();
        }
    }

    // A player's action on the Radioport is starting.
    public static func NoteAction() -> Void {
        let service = HeadsetRadioport.Get();
        if IsDefined(service) {
            service.Note();
        }
    }

    private cb func OnLoad() {
        GameInstance.GetCallbackSystem().RegisterCallback(n"Session/BeforeEnd", this, n"OnSessionEnd");
    }

    // A loaded save starts with nothing the Radioport did.
    private cb func OnSessionEnd(event: ref<GameSessionEvent>) {
        this.m_watching = false;
        this.m_putOn = false;
    }

    private func Note() {
        if !Equals(HeadsetNative.GetSetting("radioport_puts_on", "0"), "1") {
            this.m_watching = false;
            this.m_putOn = false;
            return;
        }
        let radio = HeadsetRadioport.Radio();
        if !IsDefined(radio) {
            return;
        }
        if !this.m_watching {
            this.m_watching = true;
            this.m_wasOn = radio.IsActive();
            this.m_seen = this.m_wasOn;
        }
        this.m_seenAt = HeadsetRadioport.Now();
    }

    // An action's result is what the Radioport shows once it has held for 0.2 s, a margin not yet tuned in the game.
    // Holding off for it keeps a moment of silence from counting: going from one of AudioWare Radio Framework's stations to one of the
    // game's, that mod lets go of IsActive at once, while the game's own station only starts with an event the player handles later
    // (read in its RadioEvents.reds, not measured).
    private func Update() {
        if !this.m_watching {
            return;
        }
        let radio = HeadsetRadioport.Radio();
        if !IsDefined(radio) {
            this.m_watching = false;
            return;
        }
        let on = radio.IsActive();
        let now = HeadsetRadioport.Now();
        if NotEquals(on, this.m_seen) {
            this.m_seen = on;
            this.m_seenAt = now;
            return;
        }
        if now - this.m_seenAt < 0.2 {
            return;
        }
        this.m_watching = false;
        if NotEquals(on, this.m_wasOn) {
            if on {
                this.TurnedOn();
            } else {
                this.TurnedOff();
            }
        }
    }

    // In Passthrough, the mode chosen for the Radioport; in a mode, nothing.
    private func TurnedOn() {
        this.m_putOn = false;
        if HeadsetNative.ChosenMode() != 0 {
            return;
        }
        HeadsetNative.ChooseModeForRadioport(HeadsetRadioport.ModeForRadioport());
        this.m_putOn = true;
    }

    // "Mode with the Radioport" in the menu: 2 Active Noise Cancellation, the default, or 1 Active Hearing Protection.
    // game/cet/init.lua writes it and has the same default, so change both together.
    private static func ModeForRadioport() -> Int32 {
        if Equals(HeadsetNative.GetSetting("radioport_mode", "2"), "1") {
            return 1;
        }
        return 2;
    }

    // Back to Passthrough if turning the Radioport on was what took the headset out of it, whatever mode it's in by now (user).
    private func TurnedOff() {
        let putOn = this.m_putOn;
        this.m_putOn = false;
        if putOn && HeadsetNative.ChosenMode() != 0 {
            HeadsetNative.ChooseModeForRadioport(0);
        }
    }

    // The Radioport V carries, on foot. In a vehicle, the metro included, its key and the station list work the vehicle's radio.
    private static func Radio() -> ref<PocketRadio> {
        let player = GetPlayer(GetGameInstance());
        if !IsDefined(player) {
            return null;
        }
        let vehicle = GetMountedVehicle(player);
        if IsDefined(vehicle) {
            return null;
        }
        return player.GetPocketRadio();
    }

    private static func Now() -> Float {
        return EngineTime.ToFloat(GameInstance.GetEngineTime(GetGameInstance()));
    }
}

// The Radioport key: a quick tap queues this on the player, who hands it to the Radioport (pocketRadio.script, HandleInputAction).
@wrapMethod(PlayerPuppet)
protected cb func OnRadioToggleEvent(evt: ref<RadioToggleEvent>) -> Bool {
    HeadsetRadioport.NoteAction();
    return wrappedMethod(evt);
}

// The station list, before anything else sees the choice. AudioWare Radio Framework wraps SendRadioEvent below and doesn't always call
// on through it, so this is the one that's sure to see a choice of its stations.
@wrapMethod(VehicleRadioPopupGameController)
protected func Activate() -> Void {
    HeadsetRadioport.NoteAction();
    wrappedMethod();
}

// Every radio choice the game's quick slots make goes through here, the station list's included.
@wrapMethod(QuickSlotsManager)
public final func SendRadioEvent(toggle: Bool, setStation: Bool, stationIndex: Int32) -> Void {
    HeadsetRadioport.NoteAction();
    wrappedMethod(toggle, setStation, stationIndex);
}
