// Each frame: tells the plugin where everyone is and whether a car's cabin is between you, casts the sound rays it asks for,
// then refreshes the HUD. What the rays mean is worked out in the plugin. The audio itself never touches the game thread.

@if(ModuleExists("NightCoop"))
import NightCoop.*

@if(ModuleExists("NightCoop"))
public class NightCoopVoiceSystem extends ScriptableSystem {
  private let m_hud: ref<NightCoopVoiceHud>;
  private let m_hudTimer: Float;
  private let m_positionTimer: Float;
  private let m_masterTimer: Float;
  private let m_doorsLogged: array<String>;
  private let m_timeTimer: Float;
  private let m_worldTime: Float;
  private let m_diving: Bool;
  private let m_inCar: Bool;
  private let m_ourCarKey: Uint32;
  private let m_ourGlassGone: Int32;
  private let m_glassChecks: Int32;

  private func ModId() -> String {
    return "xip.nightcoop_voice.hud"; // ASCII [a-z0-9._-], stable forever
  }

  // Runs on every game load: registering again with the same id is safe, and the frame callback has to be asked for
  // again because the target is held weakly and dies with the world.
  private func OnAttach() -> Void {
    this.m_hud = new NightCoopVoiceHud();
    this.m_worldTime = 1.0;
    if NightCoopSdk.Version() == 0 {
      return;
    }
    let flags: Int32 = EnumInt(NightCoopSdkModFlag.LocalOnly);
    if NightCoopSdk.RegisterMod(this.ModId(), "NightCoop Voice HUD", NightCoopVoiceNative.Version(), 1, flags) {
      NightCoopSdk.ListenFrame(this.ModId(), this, n"OnVoiceFrame");
    }
  }

  private func OnDetach() -> Void {
    if NightCoopSdk.Version() != 0 {
      NightCoopSdk.ListenFrame(this.ModId(), null, n"");
    }
    if IsDefined(this.m_hud) {
      this.m_hud.Remove();
    }
  }

  protected cb func OnVoiceFrame(dt: Float) -> Void {
    NightCoopVoiceNative.FrameBegin();
    this.m_hudTimer += dt;
    if this.m_hudTimer >= 0.1 {
      this.m_hudTimer = 0.0;
      this.m_hud.Update();
    }
    this.m_masterTimer += dt;
    if this.m_masterTimer >= 1.0 {
      this.m_masterTimer = 0.0;
      this.ReportGameVolume();
    }
    this.m_positionTimer += dt;
    if this.m_positionTimer >= 0.033 {
      this.m_positionTimer = 0.0;
      this.UpdatePositions();
    }
    this.m_timeTimer += dt;
    if this.m_timeTimer >= 0.05 {
      this.m_timeTimer = 0.0;
      this.UpdateListenerState(dt);
    }
    this.CastSoundRays();
    NightCoopVoiceNative.FrameEnd();
  }

  private func IsDiving() -> Bool {
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) {
      return false;
    }
    let machine = GameInstance.GetBlackboardSystem(game).GetLocalInstanced(player.GetEntityID(), GetAllBlackboardDefs().PlayerStateMachine);
    return IsDefined(machine) && machine.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Swimming) == EnumInt(gamePSMSwimming.Diving);
  }

  // Tells the plugin if we're underwater and how fast the world runs. Reading the world's speed, not what caused it, makes
  // this cover every kind of slow motion. Changes are logged, to learn which ones really reach us in co-op.
  private func UpdateListenerState(dt: Float) -> Void {
    let time = GameInstance.GetTimeSystem(this.GetGameInstance());
    let now = time.IsTimeDilationActive() ? time.GetActiveTimeDilation() : 1.0;
    if AbsF(now - this.m_worldTime) > 0.02 {
      this.m_worldTime = now;
      NightCoopSdk.Log(this.ModId(), 1, "time: the world runs at " + FloatToStringPrec(now, 2) + ", frame dt " + FloatToStringPrec(dt, 4));
    }
    let diving = this.IsDiving();
    if NotEquals(diving, this.m_diving) {
      this.m_diving = diving;
      NightCoopSdk.Log(this.ModId(), 1, diving ? "water: diving" : "water: back up");
    }
    NightCoopVoiceNative.SetListenerState(diving, now, this.m_inCar);
  }

  private func ReportGameVolume() -> Void {
    let master = GameInstance.GetSettingsSystem(this.GetGameInstance()).GetVar(n"/audio/volume", n"MasterVolume") as ConfigVarInt;
    if IsDefined(master) {
      NightCoopVoiceNative.SetGameMaster(Cast<Float>(master.GetValue()));
    }
  }

  // Once per door state, so the logs tell that doors are being found.
  private func NoteDoor(state: Int32) -> Void {
    let line = "rays: a " + (state == NightCoopVoiceDoors.Closed() ? "closed" : "open") + " door found through Dynamic";
    if !ArrayContains(this.m_doorsLogged, line) {
      ArrayPush(this.m_doorsLogged, line);
      NightCoopSdk.Log(this.ModId(), 1, line);
    }
  }

  // The plugin says when it's spent enough of this frame.
  private func CastSoundRays() -> Void {
    let queries = GameInstance.GetSpatialQueriesSystem(this.GetGameInstance());
    while NightCoopVoiceNative.NextRay() {
      this.CastSoundRay(queries, NightCoopVoiceNative.RayFrom(), NightCoopVoiceNative.RayTo(), NightCoopVoiceNative.RayGroups());
    }
  }

  // Doors are in the Dynamic group, not Static (tested in the CET console, and every door the logs have shown), so only a
  // line that's clear of walls asks there, and only a door counts: a crate shouldn't muffle anybody. Nothing here keeps a
  // TraceResult past this call.
  private func CastSoundRay(queries: ref<SpatialQueriesSystem>, from: Vector4, to: Vector4, groups: Int32) -> Void {
    let none = new Vector4(0.0, 0.0, 0.0, 0.0);
    if groups != 2 {
      let wall: TraceResult;
      queries.SyncRaycastByCollisionGroup(from, to, n"Static", wall, false, false);
      if TraceResult.IsValid(wall) {
        NightCoopVoiceNative.ReportRay(1, Vector4.Vector3To4(wall.position), Vector4.Vector3To4(wall.normal), wall.material);
        return;
      }
    }
    if groups != 0 {
      let other: TraceResult;
      queries.SyncRaycastByCollisionGroup(from, to, n"Dynamic", other, false, false);
      if TraceResult.IsValid(other) {
        let door = NightCoopVoiceDoorAt(other);
        if door != NightCoopVoiceDoors.None() {
          this.NoteDoor(door);
          if door == NightCoopVoiceDoors.Closed() {
            NightCoopVoiceNative.ReportRay(2, Vector4.Vector3To4(other.position), none, n"");
            return;
          }
        }
      }
    }
    NightCoopVoiceNative.ReportRay(0, to, none, n"");
  }

  private func VehicleOf(peer: Int32, body: wref<GameObject>) -> wref<VehicleObject> {
    let game = this.GetGameInstance();
    let reference: Uint64 = NightCoopSdk.PartnerVehicle(peer);
    if reference != 0ul {
      let entity = GameInstance.FindEntityByID(game, NightCoopSdk.EntityOfRef(reference)) as VehicleObject;
      if IsDefined(entity) {
        return entity;
      }
    }
    let vehicle: wref<VehicleObject>;
    if IsDefined(body) {
      VehicleComponent.GetVehicle(game, body, vehicle);
    }
    return vehicle;
  }

  private func IsClosedCar(vehicle: wref<VehicleObject>) -> Bool {
    return IsDefined(vehicle) && !IsDefined(vehicle as BikeObject);
  }

  private func CabinBetween(mine: wref<VehicleObject>, theirs: wref<VehicleObject>) -> Int32 {
    if IsDefined(mine) && IsDefined(theirs) && Equals(mine.GetEntityID(), theirs.GetEntityID()) {
      return 1;
    }
    if this.IsClosedCar(mine) || this.IsClosedCar(theirs) {
      return 2;
    }
    return 0;
  }

  // Where a voice comes from. Standing, 1.6 m above the body. Seated, from the head itself (the 2026-11-13 probe found it
  // 0.64-0.72 m above a seated body), or near enough when the body has no head to ask.
  private func MouthOf(body: wref<GameObject>, seated: Bool) -> Vector4 {
    let position = body.GetWorldPosition();
    if !seated {
      position.Z += 1.6;
      return position;
    }
    let puppet = body as ScriptedPuppet;
    if IsDefined(puppet) {
      let slots = puppet.GetSlotComponent();
      let head: WorldTransform;
      if IsDefined(slots) && slots.GetSlotTransform(n"Head", head) {
        return WorldPosition.ToVector4(WorldTransform.GetWorldPosition(head));
      }
    }
    position.Z += 0.7;
    return position;
  }

  // The car we sit in: described once, then where it stands, our head in it and what's open, every update. Glass is read
  // five times a second, since that means looking through all of the car's parts.
  private func UpdateOurCar(player: ref<PlayerPuppet>, mine: wref<VehicleObject>) -> Void {
    let none = new Vector4(0.0, 0.0, 0.0, 0.0);
    if !this.IsClosedCar(mine) {
      this.m_ourCarKey = 0u;
      NightCoopVoiceNative.SetOurCar(0u, none, none, none, none, none, 0, 0, 0);
      return;
    }
    NightCoopVoiceDescribeCar(-1, mine);
    let key = NightCoopVoiceCars.Key(mine);
    this.m_glassChecks += 1;
    if key != this.m_ourCarKey || this.m_glassChecks >= 6 {
      this.m_ourCarKey = key;
      this.m_glassChecks = 0;
      this.m_ourGlassGone = NightCoopVoiceGlassGone(mine);
    }
    let camera = player.GetFPPCameraComponent();
    let head = IsDefined(camera) ? Matrix.GetTranslation(camera.GetLocalToWorld()) : mine.GetWorldPosition();
    NightCoopVoiceNative.SetOurCar(key, mine.GetWorldPosition(), mine.GetWorldRight(), mine.GetWorldForward(), mine.GetWorldUp(),
      head, this.m_ourGlassGone, NightCoopVoiceCars.WindowsDown(mine), NightCoopVoiceCars.DoorsOpen(mine));
  }

  // A partner's closed car that we aren't sharing: described once, then where it stands. What's open on it they tell us.
  private func UpdatePeerCar(peer: Int32, mine: wref<VehicleObject>, theirs: wref<VehicleObject>) -> Void {
    let none = new Vector4(0.0, 0.0, 0.0, 0.0);
    if !this.IsClosedCar(theirs) || this.CabinBetween(mine, theirs) == 1 {
      NightCoopVoiceNative.SetPeerCar(peer, 0u, none, none, none, none);
      return;
    }
    NightCoopVoiceDescribeCar(peer, theirs);
    NightCoopVoiceNative.SetPeerCar(peer, NightCoopVoiceCars.Key(theirs), theirs.GetWorldPosition(), theirs.GetWorldRight(),
      theirs.GetWorldForward(), theirs.GetWorldUp());
  }

  // On or in vehicles of your own, a bike included: passing each other would keep moving the radio's range, so the radio stays.
  private func ApartInVehicles(mine: wref<VehicleObject>, theirs: wref<VehicleObject>) -> Bool {
    if !IsDefined(mine) && !IsDefined(theirs) {
      return false;
    }
    return this.CabinBetween(mine, theirs) != 1;
  }

  private func UpdatePositions() -> Void {
    let count = NightCoopVoiceNative.PeerCount();
    if count == 0 {
      return;
    }
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) {
      return;
    }

    let transform: Transform;
    if !GameInstance.GetCameraSystem(game).GetActiveCameraWorldTransform(transform) {
      return;
    }
    let listener = Transform.GetPosition(transform);
    let orientation = Transform.GetOrientation(transform);
    let forward = Quaternion.GetForward(orientation);
    let right = Quaternion.GetRight(orientation);
    NightCoopVoiceNative.SetListener(listener, forward, right);

    let mine = this.VehicleOf(NightCoopSdk.LocalPeer(), player);
    this.m_inCar = this.IsClosedCar(mine);
    this.UpdateOurCar(player, mine);
    let i = 0;
    while i < count {
      let peer = NightCoopVoiceNative.PeerIdAt(i);
      if NightCoopSdk.PeerInOurWorld(peer) {
        let body = GameInstance.FindEntityByID(game, NightCoopSdk.PartnerBody(peer)) as GameObject;
        if IsDefined(body) {
          let theirs = this.VehicleOf(peer, body);
          let talker = this.MouthOf(body, IsDefined(theirs));
          let cabin = this.CabinBetween(mine, theirs);
          this.UpdatePeerCar(peer, mine, theirs);
          NightCoopVoiceNative.SetPeerSpatial(peer, talker, body.GetWorldForward(), cabin, this.ApartInVehicles(mine, theirs));
        }
      }
      i += 1;
    }
  }
}
