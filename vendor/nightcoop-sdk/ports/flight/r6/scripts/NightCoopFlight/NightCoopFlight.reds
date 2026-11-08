// SPDX-License-Identifier: MIT — Copyright (c) 2026 NightCoop (see sdk/LICENSE); Let There Be Flight is MIT by Jack Humbert (THIRD_PARTY.md)
// NightCoop port of Let There Be Flight (LTBF): flying together.
//
// NightCoop gives every shared vehicle one owner, the machine of its driver. The owner's LTBF flies it; every partner
// sees a NightCoop mirror of it, which NightCoop moves along the owner's path (kinematic, no physics of its own). Every
// frame (NightCoopSdk.ListenFrame) this bridge does three things:
//   1. Ride  — our player sits in a partner's vehicle: its flight is the driver's. LTBF's own gate keeps our player's
//              flight off for the ride.
//   2. Own   — a vehicle we lead flies: its flight goes to the partners as two entity states (key 1: flying, gravity,
//              thrusters left; key 2: the thrust and the sound, 15 Hz), and NightCoop is told the vehicle is held in the
//              air (contacts, return home, the wheel, and partners without this port see it without wheels).
//   3. Mirror — a partner's vehicle flies: LTBF's thrusters, their FX and sound are shown on our mirror, fed from the
//              owner's stream; LTBF's flight physics never run on it. Landed — LTBF puts them away, the wheels come back.
// A vehicle that changes hands in the air goes on: ours now — our LTBF takes the flight over; a partner's now — it stays a
// flying mirror until its new owner's word comes.
//
// Built only on NightCoop's public SDK and LTBF's public members. LTBF's own classes cannot be wrapped from another mod,
// so the bridge wraps a few game classes instead (at the end of the file). Without NightCoop or LTBF it compiles to nothing.

@if(ModuleExists("NightCoop"))
import NightCoop.*

// ------------------------------------------------------------------------------------------------ constants

@if(ModuleExists("NightCoop") && ModuleExists("LetThereBeFlight"))
public abstract class NcFlight {
  public static func ModId() -> String = "nightcoop.port.let_there_be_flight";
  public static func ModName() -> String = "Let There Be Flight (NightCoop port)";
  public static func ModVersion() -> String = "2.0";
  public static func Protocol() -> Int32 = 2; // the layout of the two entity states below
  // Partners without it get a note in the mods check; it changes vehicles; it puts entity states on our vehicles.
  public static func ModFlags() -> Int32 = EnumInt(NightCoopSdkModFlag.NeededByAll) | EnumInt(NightCoopSdkModFlag.ChangesWorld)
    | EnumInt(NightCoopSdkModFlag.UsesEntityState);

  public static func KeyFlight() -> Int32 = 1; // reliable, on change
  public static func KeyThrust() -> Int32 = 2; // stream, at most every ThrustEvery
  public static func ThrustEvery() -> Float = 0.066;
  public static func MaxOwn() -> Int32 = 16;

  // LTBF's gate of its VehicleFlight state machine: a status effect with the tag VehicleBlockFlight on the player
  // (DefaultTransition.IsPlayerAllowedToEnterFlight). The record is LTBF's; nothing else applies it.
  public static func BlockFlight() -> TweakDBID = t"GameplayRestriction.VehicleBlockFlight";

  public static func On() -> Bool = NightCoopSdk.Version() > 0;

  public static func Log(text: String) -> Void {
    NightCoopSdk.Log(NcFlight.ModId(), 1, text);
  }

  public static func Warn(text: String) -> Void {
    NightCoopSdk.Log(NcFlight.ModId(), 2, text);
  }

  public static func Id(id: EntityID) -> String = EntityID.ToDebugString(id);

  public static func YesNo(value: Bool) -> String = value ? "yes" : "no";
}

// ------------------------------------------------------------------------------------------------ the wire

// Key 1: version, flags (1 flying, 2 gravity off), the thrusters still attached (a bit each, 8 at most).
// Key 2: version, the force and torque LTBF's thrusters got (normalized), LTBF's 8 sound parameters; -1..1 as a byte.
@if(ModuleExists("NightCoop") && ModuleExists("LetThereBeFlight"))
public abstract class NcFlightWire {
  public static func Version() -> Int32 = 2;
  public static func Flying() -> Int32 = 1;
  public static func GravityOff() -> Int32 = 2;

  public static func FlightBytes(fc: ref<FlightComponent>, flying: Bool, gravityOff: Bool) -> array<Uint8> {
    let flags = (flying ? NcFlightWire.Flying() : 0) | (gravityOff ? NcFlightWire.GravityOff() : 0);
    let attached = 255;
    if IsDefined(fc) && IsDefined(fc.configuration) {
      attached = 0;
      let bit = 1;
      for thruster in fc.configuration.thrusters {
        if bit < 256 && thruster.attached {
          attached = attached | bit;
        }
        bit *= 2;
      }
    }
    let bytes: array<Uint8>;
    ArrayPush(bytes, Cast<Uint8>(NcFlightWire.Version()));
    ArrayPush(bytes, Cast<Uint8>(flags));
    ArrayPush(bytes, Cast<Uint8>(attached));
    return bytes;
  }

  public static func ReadFlight(bytes: array<Uint8>, m: ref<NcFlightMirror>) -> Void {
    if ArraySize(bytes) < 3 || Cast<Int32>(bytes[0]) != NcFlightWire.Version() {
      m.flying = false; // gone, or a layout we do not know
      m.gravityOff = false;
      return;
    }
    let flags = Cast<Int32>(bytes[1]);
    m.flying = (flags & NcFlightWire.Flying()) != 0;
    m.gravityOff = (flags & NcFlightWire.GravityOff()) != 0;
    m.attached = Cast<Int32>(bytes[2]);
  }

  public static func ThrustBytes(fc: ref<FlightComponent>) -> array<Uint8> {
    let force: Vector4;
    let torque: Vector4;
    for thruster in fc.configuration.thrusters {
      if thruster.attached {
        force = thruster.force; // LTBF gives every thruster the same force and torque
        torque = thruster.torque;
        break;
      }
    }
    let a = fc.audioUpdate;
    let bytes: array<Uint8>;
    ArrayPush(bytes, Cast<Uint8>(NcFlightWire.Version()));
    ArrayPush(bytes, NcFlightWire.Byte(force.X));
    ArrayPush(bytes, NcFlightWire.Byte(force.Y));
    ArrayPush(bytes, NcFlightWire.Byte(force.Z));
    ArrayPush(bytes, NcFlightWire.Byte(torque.X));
    ArrayPush(bytes, NcFlightWire.Byte(torque.Y));
    ArrayPush(bytes, NcFlightWire.Byte(torque.Z));
    ArrayPush(bytes, NcFlightWire.Byte(IsDefined(a) ? a.surge : 0.0));
    ArrayPush(bytes, NcFlightWire.Byte(IsDefined(a) ? a.lift : 0.0));
    ArrayPush(bytes, NcFlightWire.Byte(IsDefined(a) ? a.roll : 0.0));
    ArrayPush(bytes, NcFlightWire.Byte(IsDefined(a) ? a.pitch : 0.0));
    ArrayPush(bytes, NcFlightWire.Byte(IsDefined(a) ? a.yaw : 0.0));
    ArrayPush(bytes, NcFlightWire.Byte(IsDefined(a) ? a.sway : 0.0));
    ArrayPush(bytes, NcFlightWire.Byte(IsDefined(a) ? a.brake : 0.0));
    ArrayPush(bytes, NcFlightWire.Byte(IsDefined(a) ? a.damage : 0.0));
    return bytes;
  }

  public static func ReadThrust(bytes: array<Uint8>, m: ref<NcFlightMirror>) -> Void {
    if ArraySize(bytes) < 15 || Cast<Int32>(bytes[0]) != NcFlightWire.Version() {
      return;
    }
    // IFlightThruster.Update normalizes a force longer than 10 and divides a shorter one by 10: send x 10 back
    m.force = NcFlightWire.Vec(NcFlightWire.Value(bytes[1]), NcFlightWire.Value(bytes[2]), NcFlightWire.Value(bytes[3])) * 10.0;
    m.torque = NcFlightWire.Vec(NcFlightWire.Value(bytes[4]), NcFlightWire.Value(bytes[5]), NcFlightWire.Value(bytes[6]));
    m.surge = NcFlightWire.Value(bytes[7]);
    m.lift = NcFlightWire.Value(bytes[8]);
    m.roll = NcFlightWire.Value(bytes[9]);
    m.pitch = NcFlightWire.Value(bytes[10]);
    m.yaw = NcFlightWire.Value(bytes[11]);
    m.sway = NcFlightWire.Value(bytes[12]);
    m.brake = NcFlightWire.Value(bytes[13]);
    m.damage = NcFlightWire.Value(bytes[14]);
  }

  // -1..1 -> 1..255, 128 is 0 (no negative casts)
  public static func Byte(value: Float) -> Uint8 {
    return Cast<Uint8>(RoundF(ClampF(value, -1.0, 1.0) * 127.0) + 128);
  }

  public static func Value(b: Uint8) -> Float {
    return Cast<Float>(Cast<Int32>(b) - 128) / 127.0;
  }

  public static func Vec(x: Float, y: Float, z: Float) -> Vector4 {
    let v: Vector4;
    v.X = x;
    v.Y = y;
    v.Z = z;
    return v;
  }

  public static func Same(a: array<Uint8>, b: array<Uint8>) -> Bool {
    if ArraySize(a) != ArraySize(b) {
      return false;
    }
    let i = 0;
    while i < ArraySize(a) {
      if a[i] != b[i] {
        return false;
      }
      i += 1;
    }
    return true;
  }
}

// ------------------------------------------------------------------------------------------------ records

// A partner's vehicle: what its owner told us. Kept by our entity of it whether the mirror is in the world or not.
@if(ModuleExists("NightCoop") && ModuleExists("LetThereBeFlight"))
public class NcFlightMirror {
  public let entity: EntityID;
  public let flying: Bool;
  public let gravityOff: Bool;
  public let attached: Int32 = 255;
  public let shown: Bool; // LTBF's thrusters are on our mirror
  public let force: Vector4;
  public let torque: Vector4;
  public let surge: Float;
  public let lift: Float;
  public let roll: Float;
  public let pitch: Float;
  public let yaw: Float;
  public let sway: Float;
  public let brake: Float;
  public let damage: Float;
}

// A vehicle we lead that LTBF flies (or a quickhack of ours lands on): what the partners and NightCoop were told.
@if(ModuleExists("NightCoop") && ModuleExists("LetThereBeFlight"))
public class NcFlightOwn {
  public let entity: EntityID;
  public let flight: array<Uint8>; // key 1 as told
  public let thrust: array<Uint8>; // key 2 as told
  public let thrustAt: Float;
  public let air: Int32;           // NightCoopSdkAirborneFlag bits NightCoop holds it with
  public let lastResult: Int32;
}

// A quickhack of ours landed on this vehicle (from the game's thread of the hack to the system's).
@if(ModuleExists("NightCoop") && ModuleExists("LetThereBeFlight"))
public class NcFlightWatchRequest extends ScriptableSystemRequest {
  public let vehicle: EntityID;
}

// ------------------------------------------------------------------------------------------------ the system

@if(ModuleExists("NightCoop") && ModuleExists("LetThereBeFlight"))
public class NcFlightSystem extends ScriptableSystem {
  private let m_on: Bool;
  private let m_mirrors: array<ref<NcFlightMirror>>;
  private let m_own: array<ref<NcFlightOwn>>;
  private let m_blockAsked: Bool;  // LTBF's flight block applied for this ride, not seen on the player yet
  private let m_blocked: Bool;     // ... seen on the player
  private let m_ctlrOff: Bool;     // LTBF's flight controller turned off for this ride
  private let m_saidNoBlock: Bool; // said once: this LTBF has no block record

  public static func Get(game: GameInstance) -> ref<NcFlightSystem> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"NcFlightSystem") as NcFlightSystem;
  }

  public func IsOn() -> Bool = this.m_on;

  // ---------------------------------------------------------------- lifecycle

  private func OnAttach() -> Void {
    if !NcFlight.On() {
      return; // NightCoop's SDK is switched off: LTBF works as in single player
    }
    // Every load of a save attaches a new system: the same id registers again, NightCoop gives it the partners' states
    // again, and the frame is asked again (the old object is gone).
    this.m_on = NightCoopSdk.RegisterMod(NcFlight.ModId(), NcFlight.ModName(), NcFlight.ModVersion(), NcFlight.Protocol(),
      NcFlight.ModFlags());
    if !this.m_on {
      NcFlight.Warn("bridge off: NightCoop refused the registration");
      return;
    }
    NightCoopSdk.Listen(NcFlight.ModId(), this, n"OnNightCoopEvent");
    if !NightCoopSdk.ListenFrame(NcFlight.ModId(), this, n"OnFrame") {
      NcFlight.Warn("bridge off: NightCoop refused the frame");
      this.m_on = false;
      return;
    }
    NcFlight.Log("bridge on: the driver's flight goes to the partners, a partner's flight is shown on our mirror, a ride in a partner's vehicle leaves its flight to the driver");
  }

  private func OnDetach() -> Void {
    if !this.m_on {
      return;
    }
    // The world goes with the session: LTBF puts its components away itself. NightCoop keeps the mod registered (partners
    // never see it come and go), so our holds on vehicles are released here.
    for own in this.m_own {
      this.SetAir(own, 0);
    }
    ArrayClear(this.m_own);
    ArrayClear(this.m_mirrors);
    NightCoopSdk.ListenFrame(NcFlight.ModId(), null, n"None");
    NightCoopSdk.Listen(NcFlight.ModId(), null, n"None");
    this.m_on = false;
  }

  // ---------------------------------------------------------------- events: a partner's word about its vehicle

  public func OnNightCoopEvent(evt: ref<NightCoopSdkEvent>) -> Void {
    if !this.m_on || !IsDefined(evt) || evt.kind != EnumInt(NightCoopSdkEventKind.EntityState) {
      return;
    }
    if evt.a == NcFlight.KeyFlight() {
      let m = this.MirrorOf(evt.entity, true);
      let wasFlying = m.flying;
      let bytes: array<Uint8>;
      if !evt.removed {
        bytes = evt.bytes;
      }
      NcFlightWire.ReadFlight(bytes, m);
      if (m.flying && !wasFlying) || (!m.flying && wasFlying) { // redscript 0.5: no != for Bool
        NcFlight.Log("vehicle " + NcFlight.Id(m.entity) + ": its owner says flying " + NcFlight.YesNo(m.flying) + ", gravity " + (m.gravityOff ? "off" : "on") + ", thrusters " + IntToString(m.attached));
      }
      return;
    }
    if evt.a == NcFlight.KeyThrust() {
      let t = this.MirrorOf(evt.entity, false);
      if IsDefined(t) && !evt.removed {
        NcFlightWire.ReadThrust(evt.bytes, t);
      }
    }
  }

  // A quickhack of ours landed on a vehicle (LTBF's flight hacks complete through ScriptableDeviceAction.CompleteAction).
  private func OnNcFlightWatchRequest(request: ref<NcFlightWatchRequest>) -> Void {
    let vehicle = GameInstance.FindEntityByID(this.GetGameInstance(), request.vehicle) as VehicleObject;
    if this.m_on && IsDefined(vehicle) && NightCoopSdk.EntityIsMine(request.vehicle) != 0 {
      this.Watch(vehicle);
    }
  }

  // ---------------------------------------------------------------- the frame

  public func OnFrame(dt: Float) -> Void {
    if !this.m_on {
      return;
    }
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) {
      return;
    }
    let seat = GetMountedVehicle(player);
    this.Ride(game, player, seat);
    this.Own(game, seat);
    let still = GameInstance.GetPhotoModeSystem(game).IsPhotoModeActive() || GameInstance.GetTimeSystem(game).IsPausedState();
    let i = ArraySize(this.m_mirrors) - 1;
    while i >= 0 {
      if !this.Mirror(game, this.m_mirrors[i], dt, still) {
        ArrayErase(this.m_mirrors, i);
      }
      i -= 1;
    }
  }

  // ---------------------------------------------------------------- 1. ride: our player in a partner's vehicle

  private func Ride(game: GameInstance, player: ref<PlayerPuppet>, seat: wref<VehicleObject>) -> Void {
    let partners = IsDefined(seat) && NightCoopSdk.EntityIsMine(seat.GetEntityID()) == 0;
    this.SetBlock(game, player, partners);
    let ctlr = FlightController.GetInstance();
    if !IsDefined(ctlr) {
      return;
    }
    if partners {
      // LTBF hands its flight controls to whoever gets into a flying vehicle, and our flight key can still switch it on
      // before the block shows: on a partner's vehicle neither is ours. LTBF's own stop takes them back; the owner's word
      // shows the flight again next.
      let fc = seat.GetFlightComponent();
      if IsDefined(fc) && (ctlr.IsActive() || fc.hasUpdate) {
        this.PutAway(fc);
        let m = this.MirrorOf(seat.GetEntityID(), false);
        if IsDefined(m) {
          m.shown = false;
        }
        NcFlight.Log("our player's LTBF took the partner's vehicle " + NcFlight.Id(seat.GetEntityID()) + " — given back to its owner");
      }
      if ctlr.IsEnabled() {
        ctlr.Disable(); // no "activate flight" hint on a partner's vehicle
        this.m_ctlrOff = true;
      }
      return;
    }
    if this.m_ctlrOff {
      this.m_ctlrOff = false;
      if IsDefined(seat) && !ctlr.IsEnabled() {
        ctlr.Enable(); // the vehicle is ours now; out of it, LTBF disabled the controller itself on the way out
      }
    }
  }

  // LTBF's block on our player, by what is seen each frame: on for a ride in a partner's vehicle, off otherwise. Status
  // effects land through a queue, so a block asked for is not asked again until it shows.
  private func SetBlock(game: GameInstance, player: ref<PlayerPuppet>, want: Bool) -> Void {
    let id = NcFlight.BlockFlight();
    let has = GameInstance.GetStatusEffectSystem(game).HasStatusEffect(player.GetEntityID(), id);
    if has && want && !this.m_blocked {
      NcFlight.Log("our player rides in a partner's vehicle — LTBF's flight is the driver's (VehicleBlockFlight)");
    }
    if !has && this.m_blocked {
      NcFlight.Log("our player is out of the partner's vehicle — LTBF's flight is ours again");
    }
    this.m_blocked = has && want;
    if want {
      if has {
        this.m_blockAsked = false;
        return;
      }
      if this.m_blockAsked {
        return;
      }
      if !IsDefined(TweakDBInterface.GetStatusEffectRecord(id)) {
        if !this.m_saidNoBlock {
          this.m_saidNoBlock = true;
          NcFlight.Warn("this LTBF has no GameplayRestriction.VehicleBlockFlight (an older LTBF?) — a ride in a partner's vehicle is not blocked");
        }
        return;
      }
      this.m_blockAsked = StatusEffectHelper.ApplyStatusEffect(player, id);
      return;
    }
    this.m_blockAsked = false;
    if has {
      StatusEffectHelper.RemoveStatusEffect(player, id); // also one left from a save, or asked for on a mount of our own
    }
  }

  // ---------------------------------------------------------------- 2. own: vehicles we lead that fly

  private func Own(game: GameInstance, seat: wref<VehicleObject>) -> Void {
    let inSession = NightCoopSdk.InSession();
    if inSession && IsDefined(seat) {
      let fc = seat.GetFlightComponent();
      if IsDefined(fc) && fc.active && NightCoopSdk.EntityIsMine(seat.GetEntityID()) != 0 {
        this.Watch(seat); // ours (or not shared yet): LTBF flies it for our player, driver or passenger
      }
    }
    let now = EngineTime.ToFloat(GameInstance.GetSimTime(game));
    let i = ArraySize(this.m_own) - 1;
    while i >= 0 {
      let own = this.m_own[i];
      if !this.TickOwn(game, own, now, inSession) {
        this.SetAir(own, 0);
        ArrayErase(this.m_own, i);
      }
      i -= 1;
    }
  }

  // false — forget it
  private func TickOwn(game: GameInstance, own: ref<NcFlightOwn>, now: Float, inSession: Bool) -> Bool {
    let vehicle = GameInstance.FindEntityByID(game, own.entity) as VehicleObject;
    if !inSession || !IsDefined(vehicle) {
      return false; // no partners to tell, or the vehicle is gone
    }
    let fc = vehicle.GetFlightComponent();
    let flying = IsDefined(fc) && fc.active;
    let gravityOff = !vehicle.HasGravity();
    let mine = NightCoopSdk.EntityIsMine(own.entity);
    if mine == 0 {
      this.HandedOver(vehicle, fc, gravityOff);
      return false;
    }
    if mine != 1 {
      // not shared (no partner near enough): told in full when NightCoop shares it
      this.SetAir(own, 0);
      ArrayClear(own.flight);
      ArrayClear(own.thrust);
      return flying || gravityOff;
    }
    let flight = NcFlightWire.FlightBytes(fc, flying, gravityOff);
    if !NcFlightWire.Same(flight, own.flight) {
      let result = NightCoopSdk.SetEntityStateBytes(NcFlight.ModId(), own.entity, NcFlight.KeyFlight(), flight, false);
      if result >= 0 {
        own.flight = flight;
        NcFlight.Log("our vehicle " + NcFlight.Id(own.entity) + ": flying " + NcFlight.YesNo(flying) + ", gravity " + (gravityOff ? "off" : "on") + ", thrusters " + IntToString(Cast<Int32>(flight[2])) + " — told to the partners");
      } else {
        if result != own.lastResult {
          NcFlight.Warn("our vehicle " + NcFlight.Id(own.entity) + ": its flight is not told to the partners (" + IntToString(result) + ") — tried again every frame");
        }
      }
      own.lastResult = result;
    }
    if flying && (ArraySize(own.thrust) == 0 || now - own.thrustAt >= NcFlight.ThrustEvery() || now < own.thrustAt) {
      let thrust = NcFlightWire.ThrustBytes(fc);
      if !NcFlightWire.Same(thrust, own.thrust) && NightCoopSdk.SetEntityStateBytes(NcFlight.ModId(), own.entity, NcFlight.KeyThrust(), thrust, true) >= 0 {
        own.thrust = thrust;
        own.thrustAt = now;
      }
    }
    if !flying && ArraySize(own.thrust) > 0 {
      NightCoopSdk.ClearEntityState(NcFlight.ModId(), own.entity, NcFlight.KeyThrust());
      ArrayClear(own.thrust);
    }
    let air = 0;
    if flying {
      air = EnumInt(NightCoopSdkAirborneFlag.Hold) | EnumInt(NightCoopSdkAirborneFlag.NoWheels); // LTBF hides its wheels
    } else {
      if gravityOff {
        air = EnumInt(NightCoopSdkAirborneFlag.Hold);
      }
    }
    this.SetAir(own, air);
    // landed (or never flew: a quickhack that did not switch it on), and the partners know it
    return flying || gravityOff || !NcFlightWire.Same(flight, own.flight);
  }

  // NightCoop made our flying vehicle a partner's (they took the wheel, it went home): their word leads it now. Our LTBF's
  // physics must not fight NightCoop's mirror; its thrusters stay on, a flying mirror, until that word comes.
  private func HandedOver(vehicle: ref<VehicleObject>, fc: ref<FlightComponent>, gravityOff: Bool) -> Void {
    if !IsDefined(fc) || !fc.active {
      return;
    }
    fc.hasUpdate = false;
    let m = this.MirrorOf(vehicle.GetEntityID(), true);
    m.flying = true;
    m.gravityOff = gravityOff;
    m.shown = true;
    NcFlight.Log("our flying vehicle " + NcFlight.Id(m.entity) + " is a partner's now — our LTBF's physics are off, it flies on as their mirror");
  }

  public func Watch(vehicle: wref<VehicleObject>) -> Void {
    let entity = vehicle.GetEntityID();
    for own in this.m_own {
      if Equals(own.entity, entity) {
        return;
      }
    }
    if ArraySize(this.m_own) >= NcFlight.MaxOwn() {
      this.SetAir(this.m_own[0], 0);
      ArrayErase(this.m_own, 0);
    }
    let made = new NcFlightOwn();
    made.entity = entity;
    ArrayPush(this.m_own, made);
  }

  // What NightCoop holds the vehicle with (SetEntityAirborneFlags; 0 — on the ground).
  private func SetAir(own: ref<NcFlightOwn>, air: Int32) -> Void {
    if air != own.air && NightCoopSdk.SetEntityAirborneFlags(NcFlight.ModId(), own.entity, air) >= 0 {
      own.air = air;
    }
  }

  // ---------------------------------------------------------------- 3. mirror: a partner's vehicle that flies

  // false — forget it
  private func Mirror(game: GameInstance, m: ref<NcFlightMirror>, dt: Float, still: Bool) -> Bool {
    let mine = NightCoopSdk.EntityIsMine(m.entity);
    let vehicle = GameInstance.FindEntityByID(game, m.entity) as VehicleObject;
    let fc: ref<FlightComponent>;
    if IsDefined(vehicle) {
      fc = vehicle.GetFlightComponent();
    }
    if mine == 1 {
      this.TakenOver(vehicle, fc, m);
      return false;
    }
    if mine != 0 {
      // NightCoop does not sync it any more (the session is over, it is not shared)
      this.Hide(fc, m, "is not a partner's mirror any more");
      return false;
    }
    if m.flying && NightCoopSdk.PeerHasMod(NcFlight.ModId(), NightCoopSdk.EntityLeader(m.entity)) == 0 {
      m.flying = false; // its owner has no port (it changed hands): nobody flies it there
    }
    if IsDefined(vehicle) {
      let hasGravity = vehicle.HasGravity();
      if (hasGravity && m.gravityOff) || (!hasGravity && !m.gravityOff) {
        vehicle.EnableGravity(!m.gravityOff); // the flag only (NightCoop moves the mirror): right if it becomes ours
      }
    }
    // Landed, destroyed, streamed out or not spawned yet, or LTBF has no flight component on this vehicle (switched off
    // for it — wheels, as LTBF would show): nothing shown now. The word is kept while the owner says it is in the air.
    if !m.flying || !IsDefined(fc) || vehicle.IsDestroyed() {
      this.Hide(fc, m, m.flying ? "destroyed" : "landed");
      return m.flying || m.gravityOff;
    }
    if !m.shown || !fc.active {
      m.shown = this.Show(fc); // LTBF not set up yet — the next frame
      if m.shown {
        NcFlight.Log("mirror " + NcFlight.Id(m.entity) + ": its owner flies it — LTBF's thrusters, FX and sound are shown here");
      }
      return true;
    }
    fc.hasUpdate = false; // the mirror's physics are NightCoop's, never LTBF's
    this.Detached(fc, m.attached);
    if !still {
      this.Feed(fc, m, dt);
    }
    return true;
  }

  // LTBF's own Activate without its flight physics: hasUpdate off at once (no forces, no ForceEnablePhysics), and the
  // controls are not handed to a player in the vehicle (isPlayerMounted off for the call).
  private func Show(fc: ref<FlightComponent>) -> Bool {
    if !IsDefined(fc.configuration) {
      return false;
    }
    if !fc.active {
      let mounted = fc.isPlayerMounted;
      fc.isPlayerMounted = false;
      fc.Activate(true);
      fc.isPlayerMounted = mounted;
    }
    fc.hasUpdate = false;
    return fc.active;
  }

  // LTBF's own stop: thrusters, FX, sound, colliders away, the wheels back, a player's controls back — silent.
  private func PutAway(fc: ref<FlightComponent>) -> Void {
    if fc.active {
      fc.Deactivate(true);
    }
    fc.hasUpdate = false;
  }

  private func Hide(fc: ref<FlightComponent>, m: ref<NcFlightMirror>, why: String) -> Void {
    if m.shown && IsDefined(fc) {
      this.PutAway(fc);
      NcFlight.Log("mirror " + NcFlight.Id(m.entity) + ": " + why + " — LTBF's thrusters are put away, the wheels are back");
    }
    m.shown = false;
  }

  // The vehicle is ours now while its owner flew it (we took the wheel, it came home to us): our LTBF goes on with the
  // flight; with our player in it, LTBF hands them the controls.
  private func TakenOver(vehicle: ref<VehicleObject>, fc: ref<FlightComponent>, m: ref<NcFlightMirror>) -> Void {
    if !IsDefined(fc) {
      return;
    }
    if m.shown {
      this.PutAway(fc);
    }
    if m.flying && !vehicle.IsDestroyed() {
      fc.Activate(true);
      this.Watch(vehicle);
      NcFlight.Log("vehicle " + NcFlight.Id(m.entity) + " is ours now while it flies — our LTBF goes on with the flight");
    }
  }

  // A thruster the owner lost (the game threw the part off) goes from our mirror too: LTBF's Detach stops its FX and
  // sound, the mesh is hidden here.
  private func Detached(fc: ref<FlightComponent>, mask: Int32) -> Void {
    let lost = false;
    let bit = 1;
    for thruster in fc.configuration.thrusters {
      if bit < 256 && thruster.attached && (mask & bit) == 0 {
        thruster.Detach();
        if IsDefined(thruster.meshComponent) {
          thruster.meshComponent.visualScale = new Vector3(0.0, 0.0, 0.0);
          thruster.meshComponent.Toggle(false);
        }
        lost = true;
      }
      bit *= 2;
    }
    if lost {
      fc.thrusterTensor = fc.configuration.GetThrusterTensor();
    }
  }

  // What FlightComponent.OnUpdate does for the look and the sound, from the owner's stream.
  private func Feed(fc: ref<FlightComponent>, m: ref<NcFlightMirror>, dt: Float) -> Void {
    let a = fc.audioUpdate;
    if IsDefined(fc.stats) && IsDefined(a) { // FlightComponent.stats is LTBF's private field; LTBF's thrusters read it too
      fc.stats.UpdateDynamic();
      a.surge = m.surge;
      a.lift = m.lift;
      a.roll = m.roll;
      a.pitch = m.pitch;
      a.yaw = m.yaw;
      a.sway = m.sway;
      a.brake = MaxF(m.brake, 0.0);
      a.damage = MaxF(m.damage, 0.0);
      fc.UpdateAudioParams(dt);
    }
    for thruster in fc.configuration.thrusters {
      thruster.Update(m.force, m.torque);
    }
  }

  private func MirrorOf(entity: EntityID, create: Bool) -> ref<NcFlightMirror> {
    for m in this.m_mirrors {
      if Equals(m.entity, entity) {
        return m;
      }
    }
    if !create {
      return null;
    }
    let made = new NcFlightMirror();
    made.entity = entity;
    ArrayPush(this.m_mirrors, made);
    return made;
  }
}

// ------------------------------------------------------------------------------------------------ the game's classes

// Our player gets into a vehicle: LTBF adds its VehicleFlight state machine on this same mount, and a machine that reaches
// "active" before the block stays there — so the block goes on now. This event does not run on NightCoop's thread, so it
// cannot ask whose vehicle it is: the next frame lifts the block at once when the vehicle is not a partner's.
@if(ModuleExists("NightCoop") && ModuleExists("LetThereBeFlight"))
@wrapMethod(VehicleComponent)
protected cb func OnMountingEvent(evt: ref<MountingEvent>) -> Bool {
  let result = wrappedMethod(evt);
  let vehicle = this.GetVehicle();
  if IsDefined(vehicle) {
    let system = NcFlightSystem.Get(vehicle.GetGame());
    let player = GetPlayer(vehicle.GetGame());
    if IsDefined(system) && system.IsOn() && IsDefined(player) && Equals(evt.request.lowLevelMountingInfo.childId, player.GetEntityID()) {
      StatusEffectHelper.ApplyStatusEffect(player, NcFlight.BlockFlight());
    }
  }
  return result;
}

// LTBF offers its quickhacks by its replacement of this function while FlightComponent.isQuickHackable is on: not on a
// partner's vehicle (they would switch LTBF's physics on our mirror). The game's own vehicle quickhacks go to the owner
// through NightCoop.
@if(ModuleExists("NightCoop") && ModuleExists("LetThereBeFlight"))
@wrapMethod(VehicleObject)
protected func SendQuickhackCommands(shouldOpen: Bool) -> Void {
  let fc = this.GetFlightComponent();
  if shouldOpen && IsDefined(fc) && fc.isQuickHackable && NightCoopSdk.EntityIsMine(this.GetEntityID()) == 0 {
    fc.isQuickHackable = false;
    wrappedMethod(shouldOpen);
    fc.isQuickHackable = true;
    return;
  }
  wrappedMethod(shouldOpen);
}

// LTBF's flight quickhacks complete through this: the vehicle one of ours lands on is watched, so its flight goes to the
// partners even with nobody in it.
@if(ModuleExists("NightCoop") && ModuleExists("LetThereBeFlight"))
@wrapMethod(ScriptableDeviceAction)
public func CompleteAction(gameInstance: GameInstance) -> Void {
  wrappedMethod(gameInstance);
  let action = this as FlightAction;
  let system = NcFlightSystem.Get(gameInstance);
  if IsDefined(action) && IsDefined(action.m_owner) && IsDefined(system) {
    let request = new NcFlightWatchRequest();
    request.vehicle = action.m_owner.GetEntityID();
    system.QueueRequest(request);
  }
}
