// The plugin's functions. Top level on purpose: a class in a module would be named "Module.Class", and the game would
// look for a native class by that name.
public native class NightCoopVoiceNative extends IScriptable {
  public static native func Version() -> String;

  // Bits: 1 muted, 2 radio mic on, 4 voice gate open, 8 audio running, 16 in a session.
  public static native func MicState() -> Int32;
  public static native func MicLevel() -> Float;

  // Takes a fresh picture of the players; the *At functions read from it.
  public static native func PeerCount() -> Int32;
  public static native func PeerIdAt(index: Int32) -> Int32;
  public static native func PeerNameAt(index: Int32) -> String;
  // Bits: 1 direct link up, 2 direct link failed, 4 talking nearby, 8 talking on radio, 16 they muted, 32 their radio
  // mic is on, 64 on the Relay (no direct link, and their voice gets through over NightCoop).
  public static native func PeerStateAt(index: Int32) -> Int32;
  public static native func PeerPingAt(index: Int32) -> Int32;

  public static native func SetListener(position: Vector4, forward: Vector4, right: Vector4) -> Void;
  // forward: which way their body faces. cabin: 0 nothing between us, 1 same vehicle, 2 one of us is inside a car the other isn't in.
  public static native func SetPeerSpatial(peer: Int32, position: Vector4, forward: Vector4, cabin: Int32) -> Void;
  // What this player's own state does to what they hear. worldSpeed: 1 normal, below that slow motion. inCar: inside a closed car.
  public static native func SetListenerState(underwater: Bool, worldSpeed: Float, inCar: Bool) -> Void;
  // The game's Master Volume setting, 0..100: voices keep their balance with it.
  public static native func SetGameMaster(percent: Float) -> Void;
  // Around all of the voice's work in a frame, to log what it costs.
  public static native func FrameBegin() -> Void;
  public static native func FrameEnd() -> Void;
  // The plugin decides which sound rays to cast; the game casts them. While NextRay says there's another, the other three
  // describe it. groups: 0 walls, 1 walls then closed doors, 2 closed doors only.
  public static native func NextRay() -> Bool;
  public static native func RayFrom() -> Vector4;
  public static native func RayTo() -> Vector4;
  public static native func RayGroups() -> Int32;
  // result: 0 clear, 1 a wall, 2 a closed door.
  public static native func ReportRay(result: Int32, position: Vector4, normal: Vector4, material: CName) -> Void;

  public static native func ToggleMute() -> Void;
  public static native func ToggleRadio() -> Void;
  public static native func SetOverlayOpen(open: Bool) -> Void;
  // Hear yourself: 0 off, 1 clean, 2 through the radio.
  public static native func SetTest(route: Int32) -> Void;

  public static native func GetSetting(key: String, fallback: String) -> String;
  public static native func SetSetting(key: String, value: String) -> Void;

  public static native func RefreshDevices() -> Void;
  public static native func DeviceCount(capture: Bool) -> Int32;
  public static native func DeviceName(capture: Bool, index: Int32) -> String;
  public static native func DeviceId(capture: Bool, index: Int32) -> String;
}
