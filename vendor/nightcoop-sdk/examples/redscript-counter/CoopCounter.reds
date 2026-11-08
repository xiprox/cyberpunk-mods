// SPDX-License-Identifier: MIT — Copyright (c) 2026 NightCoop (see sdk/LICENSE)
// NightCoop SDK example: a shared counter in redscript.
//
// - The counter is shared state of the mod "example.counter.redscript", key "count" (decimal text). The host keeps it.
// - Bump() adds 1: on the host it sets the state, on a guest it asks the host (the same call). Then it sends a "ping"
//   message (channel 1) to everyone who has the mod.
// - Everybody gets the new value as a State event and the ping as a Message event, through the callback OnCoopEvent.
//
// Call Bump() from the CET console:
//   Game.GetScriptableSystemsContainer():Get("CoopCounterSystem"):Bump()
//
// Everything that touches NightCoop is under @if(ModuleExists("NightCoop")); without NightCoop the stub at the bottom
// keeps Bump() callable and the mod compiles and runs as before. Do NOT copy NightCoop's own .reds files into your mod.

@if(ModuleExists("NightCoop"))
import NightCoop.*

@if(ModuleExists("NightCoop"))
public class CoopCounterSystem extends ScriptableSystem {

  private func ModId() -> String {
    return "example.counter.redscript"; // ASCII [a-z0-9._-], 3..64 bytes, stable forever
  }

  // Runs on every game load: registering again with the same id is safe (it updates the entry), and Listen has to be
  // called again because the target is held weakly and dies with the world.
  private func OnAttach() -> Void {
    if NightCoopSdk.Version() == 0 {
      return; // the player switched the SDK off
    }
    // Every player should have it; the host decides the value, guests only ask. Declare what the mod uses (shared state,
    // channels): an undeclared use answers Denied.
    let flags: Int32 = EnumInt(NightCoopSdkModFlag.NeededByAll) | EnumInt(NightCoopSdkModFlag.HostAuthority)
      | EnumInt(NightCoopSdkModFlag.UsesSharedState) | EnumInt(NightCoopSdkModFlag.UsesChannels);
    if !NightCoopSdk.RegisterMod(this.ModId(), "Shared counter (redscript example)", "1.0.0", 1, flags) {
      return; // refused, for instance the id is registered by a C plugin; NightCoop's log says why
    }
    NightCoopSdk.Listen(this.ModId(), this, n"OnCoopEvent");
  }

  private func OnDetach() -> Void {
    NightCoopSdk.Listen(this.ModId(), null, n""); // stop the callback; events wait in the queue until the next Listen
  }

  // Add 1 to the shared counter and tell everyone.
  public func Bump() -> Void {
    let id: String = this.ModId();
    // Out of a session the state is purely local, so this also works as a single-player counter.
    let current: String = NightCoopSdk.GetState(id, "count"); // "" if the key is not set yet
    let next: Int32 = StringToInt(current, 0) + 1;
    let result: Int32 = NightCoopSdk.SetState(id, "count", IntToString(next));
    if result < 0 {
      NightCoopSdk.Log(id, 2, "SetState failed: " + IntToString(result));
      return;
    }
    // to = -2: every peer that has the mod. reliable = false: a missed ping does not matter.
    NightCoopSdk.Send(id, -2, 1, "bumped the counter", false);
  }

  // Called by NightCoop on the game thread, once per event. The function must take exactly one ref<NightCoopSdkEvent>.
  protected cb func OnCoopEvent(evt: ref<NightCoopSdkEvent>) -> Void {
    let id: String = this.ModId();

    if evt.kind == EnumInt(NightCoopSdkEventKind.State) {
      if Equals(evt.key, "count") {
        if evt.removed {
          NightCoopSdk.Log(id, 1, "counter removed");
        } else {
          NightCoopSdk.Log(id, 1, "count = " + evt.data + " (set by peer " + IntToString(evt.peer) + ")");
          NightCoopSdk.ShowMessage(id, "Shared counter: " + evt.data, 2.0, 0);
        };
      };
      return;
    };

    if evt.kind == EnumInt(NightCoopSdkEventKind.Message) {
      if evt.a == 1 {
        NightCoopSdk.ShowMessage(id, NightCoopSdk.PeerName(evt.peer) + " " + evt.data, 3.0, 1);
      };
      return;
    };

    if evt.kind == EnumInt(NightCoopSdkEventKind.Session) {
      if evt.a == EnumInt(NightCoopSdkSessionEvent.PeerHasMod) {
        NightCoopSdk.Log(id, 1, NightCoopSdk.PeerName(evt.peer) + " has the counter mod");
      };
      if evt.a == EnumInt(NightCoopSdkSessionEvent.PeerNoMod) {
        NightCoopSdk.Log(id, 1, NightCoopSdk.PeerName(evt.peer) + " does not have the counter mod");
      };
    };
  }
}

// Without NightCoop: same class name and method, nothing happens.
@if(!ModuleExists("NightCoop"))
public class CoopCounterSystem extends ScriptableSystem {

  public func Bump() -> Void {
  }
}
