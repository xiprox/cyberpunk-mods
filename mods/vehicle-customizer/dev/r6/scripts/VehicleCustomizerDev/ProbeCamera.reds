// Development only (vehicle-customizer/RECORD.md, tool probe 5 of 2026-11-07): a live picture of a car part.
// The game's TV streaming camera (base\media\tv\entities\streaming_cameras\streaming_camera.ent) is one
// render-to-texture camera component, off in the file, 1280 by 600, field of view 20, drawing into
// streaming_camera_dynamic_texture.dtex; streaming_camera_ink_atlas.inkatlas shows that texture. The probe job
// spawns the camera aimed at a part, switches it on, and shows the atlas in an image on the HUD.
module VehicleCustomizerDev

public class ProbeCamera extends ScriptableSystem {
    private let m_id: EntityID;
    private let m_feed: wref<inkImage>;

    public func Spawn(position: Vector4, orientation: Quaternion) -> Bool {
        this.Remove();
        let spec = new DynamicEntitySpec();
        spec.templatePath = r"base\\media\\tv\\entities\\streaming_cameras\\streaming_camera.ent";
        spec.position = position;
        spec.orientation = orientation;
        spec.alwaysSpawned = true;
        spec.persistState = false;
        spec.persistSpawn = false;
        this.m_id = GameInstance.GetDynamicEntitySystem().CreateEntity(spec);
        return EntityID.IsDefined(this.m_id);
    }

    public func IsHere() -> Bool {
        return IsDefined(GameInstance.FindEntityByID(this.GetGameInstance(), this.m_id));
    }

    private func Camera() -> ref<entRenderToTextureCameraComponent> {
        let entity = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_id);
        if !IsDefined(entity) {
            return null;
        }
        return entity.FindComponentByType(n"entRenderToTextureCameraComponent") as entRenderToTextureCameraComponent;
    }

    // Switches the camera on with these settings; what it found, for the report.
    public func Enable(fov: Float, depthCut: Float, plainBackground: Bool) -> String {
        let camera = this.Camera();
        if !IsDefined(camera) {
            return "no camera component on the spawned entity";
        }
        camera.Toggle(false);
        camera.fov = fov;
        camera.depthCutDistance = depthCut;
        camera.overrideBackgroundColor = plainBackground;
        camera.backgroundColor = new Color(Cast<Uint8>(40u), Cast<Uint8>(44u), Cast<Uint8>(52u), Cast<Uint8>(255u));
        camera.Toggle(true);
        return "on: " + ToString(camera.resolutionWidth) + " by " + ToString(camera.resolutionHeight) + ", fov "
            + FloatToString(camera.fov) + ", depth cut " + FloatToString(camera.depthCutDistance) + ", plain background "
            + ToString(camera.overrideBackgroundColor);
    }

    // Second camera run: the first changed settings before switching it on and saw no picture (dark, then
    // see-through), so first nothing but the switch, then a render frequency (no game file sets one).
    public func SwitchOnly(on: Bool) -> String {
        let camera = this.Camera();
        if !IsDefined(camera) {
            return "no camera component on the spawned entity";
        }
        camera.Toggle(on);
        return this.Describe();
    }

    public func SetFrequency(frequency: Int32) -> String {
        let camera = this.Camera();
        if !IsDefined(camera) {
            return "no camera component";
        }
        camera.Toggle(false);
        camera.renderFrequency = Cast<Uint32>(frequency);
        camera.Toggle(true);
        return this.Describe();
    }

    public func Describe() -> String {
        let camera = this.Camera();
        if !IsDefined(camera) {
            return "no camera component";
        }
        return "enabled " + ToString(camera.IsEnabled()) + ", frequency " + ToString(camera.renderFrequency) + ", phase "
            + ToString(camera.renderPhase) + ", fov " + FloatToString(camera.fov) + ", streaming distance "
            + FloatToString(camera.streamingDistance) + ", virtual camera " + NameToString(camera.virtualCameraName);
    }

    // Third camera run: the second run's picture was right but very dark, so the image's tint brightens it
    // (ink takes HDR tints above 1).
    public func SetBrightness(factor: Float) {
        if IsDefined(this.m_feed) {
            this.m_feed.SetTintColor(new HDRColor(factor, factor, factor, 1.0));
        }
    }

    public func ShowFeed() -> Bool {
        if IsDefined(this.m_feed) {
            return true;
        }
        let root = GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer").GetVirtualWindow();
        if !IsDefined(root) {
            return false;
        }
        let image = new inkImage();
        image.SetName(n"vcdev_camera_feed");
        image.SetAtlasResource(r"base\\media\\tv\\entities\\streaming_cameras\\streaming_camera_ink_atlas.inkatlas");
        // As the game's own TV layout has it (streaming_camera_ink_widget.inkwidget): part "stuff", filling.
        image.SetTexturePart(n"stuff");
        image.SetContentHAlign(inkEHorizontalAlign.Fill);
        image.SetContentVAlign(inkEVerticalAlign.Fill);
        image.SetSize(960.0, 450.0);
        image.SetMargin(new inkMargin(60.0, 260.0, 0.0, 0.0));
        image.Reparent(root);
        this.m_feed = image;
        return true;
    }

    public func Remove() {
        if IsDefined(this.m_feed) {
            this.m_feed.SetVisible(false);
            let parent = this.m_feed.GetParentWidget() as inkCompoundWidget;
            if IsDefined(parent) {
                parent.RemoveChild(this.m_feed);
            }
        }
        if EntityID.IsDefined(this.m_id) {
            GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_id);
        }
    }
}
