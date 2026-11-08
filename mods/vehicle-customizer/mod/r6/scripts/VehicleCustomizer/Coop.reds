// Vehicle Customizer: co-op through NightCoop's SDK (vehicle-customizer/RECORD.md; nightcoop-sdk/docs).
// In a session each car of ours has one build for everyone, in NightCoop's shared state: one key per record (one
// record is one car in a session), kept by the host, sent to late joiners, cleared when the session ends. A change
// goes in as "c|<build>" and every player who owns the car keeps it in their save, whoever made it; an owner's car
// that comes out puts its saved build in as "s|<build>" when the session has none (VCEngine, "co-op"). Each player
// also puts in the list of shop cars they own, so buying in a session skips copies a player there has. A partner
// without the mod sees each pool copy as the car it was made from (FallbackSet). Cars come from V's garage the
// game's way, so NightCoop syncs them like any player car. NightCoop is called only on the game thread, from its
// frame and events (VCEngine, "calls into NightCoop"). Without NightCoop none of this is compiled and every change is
// simply the player's own.
module VehicleCustomizer

@if(ModuleExists("NightCoop"))
import NightCoop.*

@if(ModuleExists("NightCoop"))
public class VCCoop extends ScriptableSystem {
    private let m_on: Bool;
    // This world's first frame is past (OnFrame), and the time since the last once-a-second work.
    private let m_loaded: Bool;
    private let m_clock: Float;

    // The mod's id with NightCoop: the same on every player's PC and never changed.
    public static func Id() -> String {
        return "xip.vehiclecustomizer";
    }

    private func OnAttach() {
        if NightCoopSdk.Version() == 0 {
            FTLog("[VehicleCustomizer] co-op: NightCoop's SDK is switched off");
            return;
        }
        // Shared state: the session's builds and each player's list of shop cars. Cars come from V's garage the
        // game's way, so the mod spawns nothing of its own (2026-11-07).
        let flags = EnumInt(NightCoopSdkModFlag.UsesSharedState) | EnumInt(NightCoopSdkModFlag.UsesFallbacks);
        // Protocol 2: builds go through shared state since 2026-11-07, which the first build (entity state) can't
        // read, so players on it don't exchange anything with this one.
        // Protocol 3 (2026-11-07, evening): builds name rims and tires apart (rims=, tires=), which a protocol 2
        // build would drop, so the two don't exchange builds; everyone updates together.
        if !NightCoopSdk.RegisterMod(VCCoop.Id(), "Vehicle Customizer", "0.3.0", 3, flags) {
            FTLog("[VehicleCustomizer] co-op: NightCoop didn't take the registration");
            return;
        }
        NightCoopSdk.Listen(VCCoop.Id(), this, n"OnCoopEvent");
        if !NightCoopSdk.ListenFrame(VCCoop.Id(), this, n"OnFrame") {
            FTLog("[VehicleCustomizer] co-op: NightCoop didn't take the frame callback");
        }
        this.m_on = true;
        let fallbacks = 0;
        let kind = EnumInt(NightCoopSdkFallbackKind.Vehicle);
        for cat in VCData.Catalogs() {
            let base = VCData.Text(cat, "base");
            if StrLen(base) > 0 {
                for record in VCData.Pool(cat) {
                    if NightCoopSdk.FallbackSet(VCCoop.Id(), kind, TDBID.ToStringDEBUG(record), base) >= 0 {
                        fallbacks += 1;
                    }
                }
            }
        }
        FTLog(s"[VehicleCustomizer] co-op: registered with NightCoop; \(fallbacks) pool copies fall back to their base car for partners without the mod");
    }

    protected cb func OnCoopEvent(evt: ref<NightCoopSdkEvent>) -> Void {
        let engine = VCEngine.Get(this.GetGameInstance());
        let shop = VCShop.Get(this.GetGameInstance());
        if !IsDefined(engine) {
            return;
        }
        if evt.kind == EnumInt(NightCoopSdkEventKind.State) {
            // "own.<peer>": a player's list of the shop cars they own; anything else: a car's build.
            if StrBeginsWith(evt.key, VCOwnKeyPrefix()) {
                if IsDefined(shop) {
                    shop.OnOwnedList(evt.key, evt.removed ? "" : evt.data);
                }
            } else {
                engine.OnSessionState(evt.key, evt.removed ? "" : evt.data, evt.peer);
            }
        } else if evt.kind == EnumInt(NightCoopSdkEventKind.Session) {
            // Shares, owners' builds and our list put in belong to one session. The session's state itself comes and
            // goes by NightCoop's own events: joining clears a guest's state and the host's arrives, the end clears it.
            if evt.a == EnumInt(NightCoopSdkSessionEvent.SessionStart) {
                engine.ForgetSeeds();
                if IsDefined(shop) {
                    shop.OwnedChanged();
                }
            } else if evt.a == EnumInt(NightCoopSdkSessionEvent.SessionEnd) {
                engine.ForgetSession();
                if IsDefined(shop) {
                    shop.ForgetOwned();
                }
            }
        }
    }

    // NightCoop's frame, on the game thread, every frame while a world is loaded (ListenFrame): the only place besides
    // its events where the mod calls NightCoop (VCEngine, "calls into NightCoop"). Each frame: whether we're in a
    // session, and the engine's waiting writes. Once a second in a session: partners' names and the cars they lead,
    // spawns to share, our list of shop cars, owners' builds to put in. On a world's first frame in a session: the
    // session's state as NightCoop holds it here (a guest gets the host's state before it loads the host's world,
    // which starts the mod's systems afresh).
    public func OnFrame(dt: Float) -> Void {
        let engine = VCEngine.Get(this.GetGameInstance());
        let shop = VCShop.Get(this.GetGameInstance());
        if !IsDefined(engine) || !IsDefined(shop) {
            return;
        }
        let inSession = NightCoopSdk.InSession();
        if inSession && !this.m_loaded {
            engine.LoadSession();
            let peers = NightCoopSdk.Peers();
            for peer in peers {
                let key = VCOwnKeyPrefix() + ToString(peer);
                if NightCoopSdk.HasState(VCCoop.Id(), key) {
                    shop.OnOwnedList(key, NightCoopSdk.GetState(VCCoop.Id(), key));
                }
            }
            shop.OwnedChanged();
        }
        this.m_loaded = true;
        engine.OnCoopFrame(inSession);
        this.m_clock += dt;
        if this.m_clock < 1.0 {
            return;
        }
        this.m_clock = 0.0;
        if !inSession {
            return;
        }
        let peers = NightCoopSdk.Peers();
        let names: array<String>;
        for peer in peers {
            ArrayPush(names, VCPeerName(peer));
        }
        engine.OnCoopSecond(peers, names);
        shop.PublishOwned();
        engine.SeedBuilds();
    }
}

// Every function below that calls NightCoop (all but VCLiveLog) is for the game thread: call it only from
// VCCoop.OnFrame or OnCoopEvent, or what they call (VCEngine, "calls into NightCoop").

// A key of the session's state ("" removes it): the host stores it and tells everyone, a guest asks the host.
// NightCoop's answer (0 done or asked, below 0 not).
@if(ModuleExists("NightCoop"))
public func VCPutState(key: String, value: String) -> Int32 {
    if !NightCoopSdk.InSession() {
        return -2;
    }
    if StrLen(value) == 0 {
        return NightCoopSdk.RemoveState(VCCoop.Id(), key);
    }
    return NightCoopSdk.SetState(VCCoop.Id(), key, value);
}

@if(!ModuleExists("NightCoop"))
public func VCPutState(key: String, value: String) -> Int32 {
    return 0;
}

// A record's value in the session's state as NightCoop holds it here, or "".
@if(ModuleExists("NightCoop"))
public func VCSessionValue(record: TweakDBID) -> String {
    if !NightCoopSdk.InSession() {
        return "";
    }
    let key = VCEngine.SessionKey(record);
    return NightCoopSdk.HasState(VCCoop.Id(), key) ? NightCoopSdk.GetState(VCCoop.Id(), key) : "";
}

@if(!ModuleExists("NightCoop"))
public func VCSessionValue(record: TweakDBID) -> String {
    return "";
}

// Whether this machine may put owners' builds in: the host always; a guest once it knows the host has the mod, by
// which time the host has sent it the session's state (so a guest doesn't put in a build over one already there).
@if(ModuleExists("NightCoop"))
public func VCStateReady() -> Bool {
    if !NightCoopSdk.InSession() {
        return false;
    }
    return NightCoopSdk.IsHost() || NightCoopSdk.PeerHasMod(VCCoop.Id(), 0) == 1;
}

@if(!ModuleExists("NightCoop"))
public func VCStateReady() -> Bool {
    return false;
}

// A player's name in NightCoop's player list (its name.txt: "xip", "B", "Bleack"), or "" out of a session.
@if(ModuleExists("NightCoop"))
public func VCPeerName(peer: Int32) -> String {
    if !NightCoopSdk.InSession() || peer < 0 {
        return "";
    }
    let name = NightCoopSdk.PeerName(peer);
    return NightCoopSdk.CleanText(name, 32);
}

@if(!ModuleExists("NightCoop"))
public func VCPeerName(peer: Int32) -> String {
    return "";
}

// Each player's list of the shop cars they own is the session's state "own.<their number>" (VCShop, "which copies
// are taken"); peer numbers hold for one session, and so does the state.
public func VCOwnKeyPrefix() -> String {
    return "own.";
}

@if(ModuleExists("NightCoop"))
public func VCOwnKey() -> String {
    return VCOwnKeyPrefix() + ToString(NightCoopSdk.LocalPeer());
}

@if(!ModuleExists("NightCoop"))
public func VCOwnKey() -> String {
    return "";
}

// Whether this machine leads a car (drives it, or it's ours and nobody else drives): out of a session, a car
// NightCoop doesn't sync, or one it says is ours.
@if(ModuleExists("NightCoop"))
public func VCLeads(vehicle: ref<VehicleObject>) -> Bool {
    if !NightCoopSdk.InSession() {
        return true;
    }
    return NightCoopSdk.EntityIsMine(vehicle.GetEntityID()) != 0;
}

@if(!ModuleExists("NightCoop"))
public func VCLeads(vehicle: ref<VehicleObject>) -> Bool {
    return true;
}

// The engine's notes into NightCoop's log too, which is written as things happen (CET's game log only reaches the
// file when the game closes, so a test couldn't read it while it ran, 2026-11-06). NightCoop takes it from any thread.
@if(ModuleExists("NightCoop"))
public func VCLiveLog(text: String) {
    NightCoopSdk.Log(VCCoop.Id(), 1, text);
}

@if(!ModuleExists("NightCoop"))
public func VCLiveLog(text: String) {}

