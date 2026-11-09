// The plugin's functions. Top level on purpose: a class in a module would be named "Module.Class", and the game would look
// for a native class by that name.
public native class HeadsetNative extends IScriptable {
  public static native func Version() -> String;
  public static native func GetSetting(key: String, fallback: String) -> String;
  public static native func SetSetting(key: String, value: String) -> Void;
  public static native func SetOverlayOpen(open: Bool) -> Void;
  // 0 nothing, otherwise a mode was just chosen: 1 Passthrough, 2 Hearing Protection, 3 Noise Cancelling. Reading clears it.
  public static native func TakeCue() -> Int32;
  // 0 nothing, 1 the key has been held long enough to open the wheel, 2 it's been let go. Reading clears it.
  public static native func TakeWheelEvent() -> Int32;
  // 0 Passthrough, 1 Active Hearing Protection, 2 Active Noise Cancellation.
  public static native func ChosenMode() -> Int32;
  // What the headset is doing right now: the chosen mode, or Hearing Protection while a radio left on borrows it from Passthrough.
  public static native func EffectiveMode() -> Int32;
  public static native func ChooseMode(mode: Int32) -> Void;
  public static native func WheelFlipY() -> Bool;
}

public class HeadsetSounds {
  public static func Play(sound: CName) -> Void {
    GameInstance.GetAudioSystem(GetGameInstance()).Play(sound);
  }
}
