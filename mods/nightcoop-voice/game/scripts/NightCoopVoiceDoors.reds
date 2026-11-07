// Tells sound rays what a door is. Finding what a ray hit takes Codeware, so without it no ray ever finds a door.

public class NightCoopVoiceDoors extends IScriptable {
  public static func None() -> Int32 {
    return 0; // what was hit isn't a door
  }

  public static func Open() -> Int32 {
    return 1;
  }

  public static func Closed() -> Int32 {
    return 2;
  }
}

@if(ModuleExists("Codeware"))
public func NightCoopVoiceDoorAt(result: script_ref<TraceResult>) -> Int32 {
  // This copy has to stay. Passing `result` straight on compiles with a "temporary" flag, and Codeware then frees the
  // caller's variable as if it were its own temporary, which crashed all three players in 0.3.0.
  let hit = Deref(result);
  let door = TraceResult.GetHitEntity(hit) as Door;
  if !IsDefined(door) {
    return NightCoopVoiceDoors.None();
  }
  let state = door.GetDevicePS() as DoorControllerPS;
  if IsDefined(state) && state.IsOpen() {
    return NightCoopVoiceDoors.Open();
  }
  return NightCoopVoiceDoors.Closed();
}

@if(!ModuleExists("Codeware"))
public func NightCoopVoiceDoorAt(result: script_ref<TraceResult>) -> Int32 {
  return NightCoopVoiceDoors.None();
}
