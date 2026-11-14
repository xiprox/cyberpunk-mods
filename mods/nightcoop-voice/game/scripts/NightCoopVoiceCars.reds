// Tells the plugin about the cars players sit in: where each window, windscreen and door is, from the game's own parts,
// and what's open. Listing a car's parts takes Codeware, so without it every car stays shut, as before.

public class NightCoopVoiceCars extends IScriptable {
  // Tells one car from another; 0 for none.
  public static func Key(vehicle: wref<VehicleObject>) -> Uint32 {
    return IsDefined(vehicle) ? EntityID.GetHash(vehicle.GetEntityID()) : 0u;
  }

  // A place in the car's frame: metres right, forward and up from its origin.
  public static func Local(vehicle: wref<VehicleObject>, world: Vector4) -> Vector4 {
    let offset = world - vehicle.GetWorldPosition();
    return new Vector4(Vector4.Dot(offset, vehicle.GetWorldRight()), Vector4.Dot(offset, vehicle.GetWorldForward()),
      Vector4.Dot(offset, vehicle.GetWorldUp()), 0.0);
  }

  // The door a part is the main panel of: 0 front left, 1 front right, 2 back left, 3 back right; -1 for anything else.
  public static func DoorOf(name: CName) -> Int32 {
    switch name {
      case n"door_fl_a": return 0;
      case n"door_fr_a": return 1;
      case n"door_bl_a": return 2;
      case n"door_br_a": return 3;
      default: return -1;
    }
  }

  // The glass the car's record lists, in its order, which every player's game shares.
  public static func GlassNames(vehicle: wref<VehicleObject>) -> array<CName> {
    let names: array<CName>;
    let record = vehicle.GetRecord();
    if !IsDefined(record) {
      return names;
    }
    let destruction = record.Destruction();
    if !IsDefined(destruction) {
      return names;
    }
    let count = destruction.GetGlassCount();
    let i = 0;
    while i < count {
      let glass = destruction.GetGlassItem(i);
      ArrayPush(names, IsDefined(glass) ? glass.Component() : n"");
      i += 1;
    }
    return names;
  }

  // Bits 0..3, front left to back right: windows wound down.
  public static func WindowsDown(vehicle: wref<VehicleObject>) -> Int32 {
    let ps = vehicle.GetVehiclePS();
    let bits = 0;
    let bit = 1;
    let i = 0;
    while i < 4 && IsDefined(ps) {
      if Equals(ps.GetWindowState(IntEnum<EVehicleDoor>(i)), EVehicleWindowState.Open) {
        bits += bit;
      }
      bit *= 2;
      i += 1;
    }
    return bits;
  }

  // Bits 0..3: doors open or torn off.
  public static func DoorsOpen(vehicle: wref<VehicleObject>) -> Int32 {
    let ps = vehicle.GetVehiclePS();
    let bits = 0;
    let bit = 1;
    let i = 0;
    while i < 4 && IsDefined(ps) {
      if NotEquals(ps.GetDoorState(IntEnum<EVehicleDoor>(i)), VehicleDoorState.Closed) {
        bits += bit;
      }
      bit *= 2;
      i += 1;
    }
    return bits;
  }

  // With everything shut, every part sits where it belongs; a wound window or a swung door has moved.
  public static func AllShut(vehicle: wref<VehicleObject>) -> Bool {
    return NightCoopVoiceCars.WindowsDown(vehicle) == 0 && NightCoopVoiceCars.DoorsOpen(vehicle) == 0;
  }
}

// Describes a car to the plugin once, when it asks and everything on the car is shut. owner: a partner's id, or -1 for ours.
@if(ModuleExists("Codeware"))
public func NightCoopVoiceDescribeCar(owner: Int32, vehicle: wref<VehicleObject>) -> Void {
  let key = NightCoopVoiceCars.Key(vehicle);
  if key == 0u || !NightCoopVoiceNative.CarNeedsParts(owner, key) || !NightCoopVoiceCars.AllShut(vehicle) {
    return;
  }
  let glass = NightCoopVoiceCars.GlassNames(vehicle);
  NightCoopVoiceNative.BeginCar(owner, key);
  let parts = vehicle.GetComponents();
  for part in parts {
    let mesh = part as MeshComponent;
    if IsDefined(mesh) {
      let index = ArrayFindFirst(glass, part.name);
      let door = NightCoopVoiceCars.DoorOf(part.name);
      if index >= 0 || door >= 0 {
        let pivot = NightCoopVoiceCars.Local(vehicle, Matrix.GetTranslation(mesh.GetLocalToWorld()));
        NightCoopVoiceNative.AddCarPart(owner, index, door, NameToString(part.name), ResourceAsyncRef.GetHash(mesh.mesh), pivot);
      }
    }
  }
  NightCoopVoiceNative.FinishCar(owner, NameToString(vehicle.GetCurrentAppearanceName()));
}

// Bit per glass index: shot out, which switches its part off.
@if(ModuleExists("Codeware"))
public func NightCoopVoiceGlassGone(vehicle: wref<VehicleObject>) -> Int32 {
  let glass = NightCoopVoiceCars.GlassNames(vehicle);
  let gone: array<Bool>;
  ArrayResize(gone, ArraySize(glass));
  let parts = vehicle.GetComponents();
  for part in parts {
    let index = ArrayFindFirst(glass, part.name);
    if index >= 0 && !part.IsEnabled() {
      gone[index] = true;
    }
  }
  let bits = 0;
  let bit = 1;
  let i = 0;
  while i < ArraySize(gone) && i < 31 {
    if gone[i] {
      bits += bit;
    }
    bit *= 2;
    i += 1;
  }
  return bits;
}

@if(!ModuleExists("Codeware"))
public func NightCoopVoiceDescribeCar(owner: Int32, vehicle: wref<VehicleObject>) -> Void {}

@if(!ModuleExists("Codeware"))
public func NightCoopVoiceGlassGone(vehicle: wref<VehicleObject>) -> Int32 {
  return 0;
}
