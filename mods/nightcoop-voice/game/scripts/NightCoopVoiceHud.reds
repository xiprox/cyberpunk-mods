// The corner display: your mic, your radio, and who's talking. Built by hand in the HUD layer (Codeware gives access to
// it), so it shows without CET and fades with the rest of the HUD in menus.

@if(ModuleExists("Codeware"))
public class NightCoopVoiceHud extends IScriptable {
  private let m_root: wref<inkCanvas>;
  private let m_mic: wref<inkText>;
  private let m_bar: wref<inkRectangle>;
  private let m_radio: wref<inkText>;
  private let m_rows: array<wref<inkText>>;

  private static func MaxRows() -> Int32 {
    return 7;
  }

  private func MakeText(parent: wref<inkCompoundWidget>, size: Int32) -> wref<inkText> {
    let text = new inkText();
    text.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
    text.SetFontStyle(n"Medium");
    text.SetFontSize(size);
    text.SetFitToContent(true);
    text.Reparent(parent);
    return text;
  }

  private func Build() -> Bool {
    let layer = GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer");
    if !IsDefined(layer) {
      return false;
    }
    let window = layer.GetVirtualWindow();
    if !IsDefined(window) {
      return false;
    }

    let root = new inkCanvas();
    root.SetName(n"NightCoopVoiceHud");
    root.SetAnchor(inkEAnchor.TopLeft);
    root.SetMargin(new inkMargin(70.0, 240.0, 0.0, 0.0));
    root.SetFitToContent(true);
    root.Reparent(window);
    this.m_root = root;

    let column = new inkVerticalPanel();
    column.SetFitToContent(true);
    column.Reparent(root);

    let micLine = new inkHorizontalPanel();
    micLine.SetFitToContent(true);
    micLine.Reparent(column);
    this.m_mic = this.MakeText(micLine, 26);

    let bar = new inkRectangle();
    bar.SetSize(new Vector2(0.0, 10.0));
    bar.SetMargin(new inkMargin(12.0, 12.0, 0.0, 0.0));
    bar.Reparent(micLine);
    this.m_bar = bar;

    this.m_radio = this.MakeText(column, 26);

    let i = 0;
    while i < NightCoopVoiceHud.MaxRows() {
      ArrayPush(this.m_rows, this.MakeText(column, 24));
      i += 1;
    }
    return true;
  }

  public func Remove() -> Void {
    if IsDefined(this.m_root) {
      let parent = this.m_root.GetParentWidget() as inkCompoundWidget;
      if IsDefined(parent) {
        parent.RemoveChild(this.m_root);
      }
    }
    this.m_root = null;
    ArrayClear(this.m_rows);
  }

  private func Red() -> HDRColor {
    return new HDRColor(1.18, 0.38, 0.35, 1.0);
  }

  private func Cyan() -> HDRColor {
    return new HDRColor(0.37, 0.96, 1.0, 1.0);
  }

  private func Yellow() -> HDRColor {
    return new HDRColor(1.0, 0.86, 0.3, 1.0);
  }

  private func Grey() -> HDRColor {
    return new HDRColor(0.62, 0.62, 0.66, 1.0);
  }

  public func Update() -> Void {
    let state = NightCoopVoiceNative.MicState();
    let inSession = (state & 16) != 0;
    let wanted = inSession && !Equals(NightCoopVoiceNative.GetSetting("hud", "1"), "0");
    if !wanted {
      if IsDefined(this.m_root) {
        this.m_root.SetVisible(false);
      }
      return;
    }
    if !IsDefined(this.m_root) && !this.Build() {
      return;
    }
    this.m_root.SetVisible(true);

    let muted = (state & 1) != 0;
    let radio = (state & 2) != 0;
    let gate = (state & 4) != 0;
    let audio = (state & 8) != 0;

    if muted {
      this.m_mic.SetText("MIC MUTED");
      this.m_mic.SetTintColor(this.Red());
    } else {
      if audio {
        this.m_mic.SetText("MIC LIVE");
      } else {
        this.m_mic.SetText("MIC WAITING FOR A LINK");
      }
      if gate {
        this.m_mic.SetTintColor(this.Cyan());
      } else {
        this.m_mic.SetTintColor(this.Grey());
      }
    }
    let level = muted ? 0.0 : NightCoopVoiceNative.MicLevel();
    this.m_bar.SetSize(new Vector2(level * 140.0, 10.0));
    this.m_bar.SetTintColor(gate ? this.Cyan() : this.Grey());

    if radio {
      this.m_radio.SetText(muted ? "RADIO ON AIR (MUTED)" : "RADIO ON AIR");
      this.m_radio.SetTintColor(this.Yellow());
    } else {
      this.m_radio.SetText("radio listening");
      this.m_radio.SetTintColor(this.Grey());
    }

    let count = NightCoopVoiceNative.PeerCount();
    let i = 0;
    while i < ArraySize(this.m_rows) {
      let row = this.m_rows[i];
      if i < count {
        let peer = NightCoopVoiceNative.PeerStateAt(i);
        let name = NightCoopVoiceNative.PeerNameAt(i);
        let relay = (peer & 64) != 0;
        let path = relay ? ", Relay" : "";
        let line = relay ? name + " - Relay" : name;
        let color = this.Grey();
        if (peer & 1) == 0 && !relay {
          line = ((peer & 2) != 0) ? name + " - no direct link" : name + " - connecting";
          color = ((peer & 2) != 0) ? this.Red() : this.Grey();
        } else {
          if (peer & 8) != 0 {
            line = name + " - radio" + path;
            color = this.Yellow();
          } else {
            if (peer & 4) != 0 {
              line = name + " - nearby" + path;
              color = this.Cyan();
            } else {
              if (peer & 32) != 0 {
                line = name + " - on air" + path;
              } else {
                if (peer & 16) != 0 {
                  line = name + " - muted" + path;
                }
              }
            }
          }
        }
        row.SetText(line);
        row.SetTintColor(color);
        row.SetVisible(true);
      } else {
        row.SetVisible(false);
      }
      i += 1;
    }
  }
}

@if(!ModuleExists("Codeware"))
public class NightCoopVoiceHud extends IScriptable {
  public func Remove() -> Void {
  }
  public func Update() -> Void {
  }
}
