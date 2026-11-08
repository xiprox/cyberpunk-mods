// In-game test for the vehicle customizer (vehicle-customizer/RECORD.md).
// Adds the Archer Quartz Nomad's front kit to the stock-look Hella test copy while the car is being built,
// since a part added to a car already in the world didn't join it. Codeware's Entity/Extract event hands
// over the car's builder before the car exists, and the builder's look takes new parts. The CET test window
// switches the kit on and off and moves it through SetKit, and reads what happened through the getters.
//
// A look change builds the car's parts through the same builder, but without the car's record (three-route
// run), so the service listens to every build that takes its look from the Hella's look file and decides
// whether it's the copy: by record when the copy is called, by a twin look's name (<look>__vc_a or __vc_b,
// added by the test's ArchiveXL patch), by entity, or by the look the test window said it was about to put
// on. Switching the copy between a look's twins makes the game build it again where it stands, which a
// "change" to the look it already has doesn't.
// Entity/Reassemble also fires on a look change; there the service only adds the kit if the build missed it.
module VehicleCustomizerTest

public class KitService extends ScriptableService {
    private let m_on: Bool;
    private let m_ahead: Float;
    private let m_up: Float;
    private let m_builds: Int32;
    private let m_note: String;
    private let m_copyId: EntityID;
    private let m_expectLook: CName;
    private let m_reassembles: Int32;
    private let m_reassembleNote: String;
    private let m_adding: Bool;
    private let m_hellaBuilds: Int32;
    private let m_hellaBuildNote: String;
    // The saved build (swapped meshes and paints), sent by the test window. When m_swapAtBuild is on, the
    // service puts it on as the copy is built, and updates the look's visual controller list to match,
    // instead of the window putting it back after the car appears.
    private let m_swapAtBuild: Bool;
    private let m_partNames: array<CName>;
    private let m_partMeshes: array<String>;
    private let m_partPaints: array<CName>;
    private let m_swapNote: String;
    private let m_lookKeeps: Int32;
    private let m_lookKeepNote: String;

    private cb func OnLoad() {
        let callbacks = GameInstance.GetCallbackSystem();
        callbacks.RegisterCallback(n"Entity/Extract", this, n"OnHellaExtract")
            .AddTarget(EntityTarget.Definition(r"base\\vehicles\\appearances\\standard\\archer_hella__basic.app"));
        callbacks.RegisterCallback(n"Entity/Attach", this, n"OnCopyAttach")
            .AddTarget(EntityTarget.RecordID(t"Vehicle.v_standard2_archer_hella_player_vctest"));
        callbacks.RegisterCallback(n"Entity/Reassemble", this, n"OnReassemble")
            .AddTarget(EntityTarget.RecordID(t"Vehicle.v_standard2_archer_hella_player_vctest"));
        this.m_note = "waiting for the copy to be built";
        this.m_reassembleNote = "none yet";
        this.m_hellaBuildNote = "none yet";
    }

    public func SetKit(on: Bool, ahead: Float, up: Float) {
        this.m_on = on;
        this.m_ahead = ahead;
        this.m_up = up;
    }

    public func SetSwapAtBuild(on: Bool) {
        this.m_swapAtBuild = on;
    }

    public func ClearParts() {
        ArrayClear(this.m_partNames);
        ArrayClear(this.m_partMeshes);
        ArrayClear(this.m_partPaints);
    }

    // mesh "" keeps the part's mesh and changes only its paint; paint None with a mesh means "default".
    public func SetPart(name: CName, mesh: String, paint: CName) {
        ArrayPush(this.m_partNames, name);
        ArrayPush(this.m_partMeshes, mesh);
        ArrayPush(this.m_partPaints, paint);
    }

    public func GetSwapNote() -> String {
        return this.m_swapNote;
    }

    // Called by the wrap below each time the game asks to reset the copy's look and is refused.
    public func NoteLookKept(look: CName, crystalCoat: Bool) {
        this.m_lookKeeps += 1;
        this.m_lookKeepNote = s"look \(NameToString(look)) kept; the game asked for the record's \(crystalCoat ? "CrystalCoat" : "own") look";
    }

    public func GetLookKeeps() -> Int32 {
        return this.m_lookKeeps;
    }

    public func GetLookKeepNote() -> String {
        return this.m_lookKeepNote;
    }

    // How the copy's saved parts stand now: whether each has the mesh and paint the build gives it.
    public func DescribeParts(entity: ref<Entity>) -> String {
        if !IsDefined(entity) {
            return "no car";
        }
        let parts = entity.GetComponents();
        let text = "";
        let i = 0;
        while i < ArraySize(this.m_partNames) {
            let state = "not on the car";
            for part in parts {
                let mesh = part as MeshComponent;
                if IsDefined(mesh) && Equals(mesh.name, this.m_partNames[i]) {
                    let ref = mesh.mesh;
                    let meshOk = StrLen(this.m_partMeshes[i]) == 0
                        || ResourceAsyncRef.GetHash(ref) == ResRef.GetHash(ResRef.FromString(this.m_partMeshes[i]));
                    state = s"mesh \(meshOk ? "as built" : "OTHER"), paint \(NameToString(mesh.meshAppearance))";
                }
            }
            text += s"\(NameToString(this.m_partNames[i])): \(state); ";
            i += 1;
        }
        return text;
    }

    // Called by the test window just before it changes the copy's look.
    public func ExpectLook(look: CName) {
        this.m_expectLook = look;
    }

    public func GetBuilds() -> Int32 {
        return this.m_builds;
    }

    public func GetNote() -> String {
        return this.m_note;
    }

    public func GetReassembleNote() -> String {
        return s"\(this.m_reassembles) seen, last: \(this.m_reassembleNote)";
    }

    public func GetHellaBuildNote() -> String {
        return s"\(this.m_hellaBuilds) seen, last: \(this.m_hellaBuildNote)";
    }

    // Sends the copy back to the garage and calls it again, as the call menu does.
    public func SendAway() {
        let garageID: GarageVehicleID;
        garageID.recordID = t"Vehicle.v_standard2_archer_hella_player_vctest";
        GameInstance.GetVehicleSystem(GetGameInstance()).DespawnPlayerVehicle(garageID);
    }

    public func CallBack() -> Bool {
        return GameInstance.GetVehicleSystem(GetGameInstance())
            .SpawnPlayerVehicle(gamedataVehicleType.Car, t"Vehicle.v_standard2_archer_hella_player_vctest", false);
    }

    private cb func OnCopyAttach(event: ref<EntityLifecycleEvent>) {
        let entity = event.GetEntity();
        if IsDefined(entity) {
            this.m_copyId = entity.GetEntityID();
        }
    }

    private cb func OnHellaExtract(event: ref<EntityBuilderEvent>) {
        this.m_hellaBuilds += 1;
        let builder = event.GetEntityBuilder();
        let look = builder.GetAppearanceName();
        let id = builder.GetEntityID();
        let hasId = EntityID.IsDefined(id);
        let how = "";
        if builder.GetRecordID() == t"Vehicle.v_standard2_archer_hella_player_vctest" {
            how = "by record";
        } else if StrContains(NameToString(look), "__vc_") {
            // A twin look (archive/pc/mod/vehiclecustomizertest.archive.xl): no game system picks one.
            how = "by twin look";
        } else if hasId && EntityID.IsDefined(this.m_copyId) && id == this.m_copyId {
            how = "by entity";
        } else if IsNameValid(this.m_expectLook) && Equals(look, this.m_expectLook) && !hasId {
            how = "by the look the window expected";
        }
        this.m_hellaBuildNote = s"record \(TDBID.ToStringDEBUG(builder.GetRecordID())), look \(NameToString(look)), "
            + s"entity \(hasId ? "given" : "not given"), the copy: \(StrLen(how) > 0 ? how : "no")";
        if StrLen(how) == 0 {
            return;
        }
        this.m_expectLook = n"";
        this.m_builds += 1;
        if this.m_swapAtBuild && builder.HasAppearance() {
            this.m_swapNote = s"build \(this.m_builds): " + this.ApplySwaps(builder.GetAppearance());
        }
        if !this.m_on {
            this.m_note = s"copy built (\(this.m_builds)) \(how) in look \(NameToString(look)); kit off";
            return;
        }
        if !builder.HasAppearance() {
            this.m_note = s"copy built (\(this.m_builds)) \(how); it had no look to add parts to";
            return;
        }
        let appearance = builder.GetAppearance();
        for part in this.MakeKit() {
            appearance.AddComponent(part);
        }
        this.m_note = s"copy built (\(this.m_builds)) \(how) in look \(NameToString(look)); kit added";
    }

    private cb func OnReassemble(event: ref<EntityLifecycleEvent>) {
        this.m_reassembles += 1;
        let entity = event.GetEntity();
        if !IsDefined(entity) {
            this.m_reassembleNote = "no entity";
            return;
        }
        if !this.m_on || this.m_adding {
            this.m_reassembleNote = s"kit \(this.m_on ? "on, being added" : "off")";
            return;
        }
        if this.HasPart(entity, n"vc_nomad_sensor") {
            this.m_reassembleNote = "kit already on";
            return;
        }
        this.m_adding = true;
        for part in this.MakeKit() {
            entity.AddComponent(part);
        }
        this.m_adding = false;
        this.m_reassembleNote = s"kit missing, added; sensor on it now: \(this.HasPart(entity, n"vc_nomad_sensor"))";
    }

    // Gives the look's parts the saved meshes and paints before the car exists, and points the visual
    // controller's entry for each at the same, since the game reloads parts from that list when the car
    // comes back into view (third run).
    private func ApplySwaps(appearance: ref<EntityBuilderAppearanceWrapper>) -> String {
        let parts = appearance.GetComponents();
        let controller: ref<entVisualControllerComponent>;
        for part in parts {
            let found = part as entVisualControllerComponent;
            if IsDefined(found) {
                controller = found;
            }
        }
        let applied = 0;
        let missing = "";
        let listed = 0;
        let i = 0;
        while i < ArraySize(this.m_partNames) {
            let name = this.m_partNames[i];
            let hasMesh = StrLen(this.m_partMeshes[i]) > 0;
            let paint = this.m_partPaints[i];
            if hasMesh && !IsNameValid(paint) {
                paint = n"default";
            }
            let done = false;
            for part in parts {
                let mesh = part as MeshComponent;
                if IsDefined(mesh) && Equals(mesh.name, name) {
                    if hasMesh {
                        mesh.mesh *= ResRef.FromString(this.m_partMeshes[i]);
                    }
                    if IsNameValid(paint) {
                        mesh.meshAppearance = paint;
                    }
                    if IsDefined(controller) && this.UpdateDependency(controller, mesh) {
                        listed += 1;
                    }
                    done = true;
                }
            }
            if done {
                applied += 1;
            } else {
                missing += NameToString(name) + " ";
            }
            i += 1;
        }
        let note = s"\(applied) of \(ArraySize(this.m_partNames)) saved parts put on, \(listed) of them in the visual controller's list";
        if StrLen(missing) > 0 {
            note += s"; not in this look: \(missing)";
        }
        if !IsDefined(controller) {
            note += "; the look has no visual controller";
        }
        return note;
    }

    // Points the controller's entry for this part at its mesh and paint, adding one if the part has none.
    private func UpdateDependency(controller: ref<entVisualControllerComponent>, part: ref<MeshComponent>) -> Bool {
        let deps = controller.appearanceDependency;
        let found = false;
        let j = 0;
        while j < ArraySize(deps) {
            if Equals(deps[j].componentName, part.name) {
                let dep = deps[j];
                dep.mesh = part.mesh;
                dep.appearanceName = part.meshAppearance;
                deps[j] = dep;
                found = true;
            }
            j += 1;
        }
        if !found {
            let dep: entVisualControllerDependency;
            dep.componentName = part.name;
            dep.mesh = part.mesh;
            dep.appearanceName = part.meshAppearance;
            ArrayPush(deps, dep);
        }
        controller.appearanceDependency = deps;
        return true;
    }

    private func HasPart(entity: ref<Entity>, name: CName) -> Bool {
        for part in entity.GetComponents() {
            if Equals(part.name, name) {
                return true;
            }
        }
        return false;
    }

    // Mounted as on the Archer Quartz Nomad (archer_quartz_nomad.app, look aldecados_01).
    private func MakeKit() -> array<ref<IComponent>> {
        let kit: array<ref<IComponent>>;
        let sensor = r"base\\vehicles\\common\\parts\\v_common__nomad\\entities\\meshes\\v_common_nomad_part__ext01_sensor_medium_02.mesh";
        let sensorShadow = r"base\\vehicles\\common\\parts\\v_common__nomad\\entities\\meshes\\v_common_nomad_part__ext01_sensor_medium_02_shadow.mesh";
        ArrayPush(kit, this.MakePart(n"vc_nomad_sensor", sensor, n"dusty_01", -0.6987, 1.8611, -0.0768, new Quaternion(0.0, 0.0, 0.0, 1.0)));
        ArrayPush(kit, this.MakeShadow(n"vc_nomad_sensor_shadow", sensorShadow, n"vc_nomad_sensor"));
        this.AddDetector(kit, n"vc_nomad_detector_1", -0.5849, 1.8777, -0.3633, new Quaternion(-0.3234716, 0.0179898, 0.2841919, 0.9023732));
        this.AddDetector(kit, n"vc_nomad_detector_2", -0.5490, 1.7580, -0.4821, new Quaternion(-0.5109810, -0.0071725, 0.2204561, 0.8308105));
        this.AddDetector(kit, n"vc_nomad_detector_3", 0.5519, 1.7663, -0.4801, new Quaternion(-0.5034177, 0.0902069, -0.2860584, 0.8103110));
        this.AddDetector(kit, n"vc_nomad_detector_4", 0.6013, 1.8779, -0.3702, new Quaternion(-0.2870721, 0.0251881, -0.2870211, 0.9135503));
        return kit;
    }

    private func AddDetector(kit: script_ref<array<ref<IComponent>>>, name: CName, x: Float, y: Float, z: Float, rotation: Quaternion) {
        ArrayPush(Deref(kit), this.MakePart(name,
            r"base\\vehicles\\common\\parts\\v_common__nomad\\entities\\meshes\\v_common_nomad_part__ext01_detector_medium_01.mesh",
            n"dusty_light_01", x, y, z, rotation));
        ArrayPush(Deref(kit), this.MakeShadow(StringToName(NameToString(name) + "_shadow"),
            r"base\\vehicles\\common\\parts\\v_common__nomad\\entities\\meshes\\v_common_nomad_part__ext01_detector_medium_01_shadow.mesh",
            name));
    }

    // A mesh part on the car's Base mount point, at an offset and a turn, moved by the kit's offset.
    private func MakePart(name: CName, mesh: ResRef, paint: CName, x: Float, y: Float, z: Float, rotation: Quaternion) -> ref<IComponent> {
        let part = new MeshComponent();
        part.name = name;
        part.mesh *= mesh;
        part.meshAppearance = paint;
        let binding = new entHardTransformBinding();
        binding.bindName = n"vehicle_slots";
        binding.slotName = n"Base";
        part.parentTransform = binding;
        let transform: WorldTransform;
        WorldTransform.SetPosition(transform, new Vector4(x, y + this.m_ahead, z + this.m_up, 1.0));
        WorldTransform.SetOrientation(transform, rotation);
        part.localTransform = transform;
        return part;
    }

    // A shadow mesh hanging off its part, as on the Quartz.
    private func MakeShadow(name: CName, mesh: ResRef, parent: CName) -> ref<IComponent> {
        let part = new MeshComponent();
        part.name = name;
        part.mesh *= mesh;
        let binding = new entHardTransformBinding();
        binding.bindName = parent;
        part.parentTransform = binding;
        return part;
    }
}

// When the player gets into a car that supports CrystalCoat, the game puts it back on its record's look
// (VehicleObject.OnMountingEvent calls this with false), and CrystalCoat Continuity does the same to a car that
// appears near the player. That undoes the twin or base look the customizer gives the copy, and the rebuild
// it causes comes by a look name the service doesn't take for the copy, so the car turns stock (RECORD.md,
// 2026-11-06). The copy keeps its look; CrystalCoat on it goes with it.
@wrapMethod(VehicleComponent)
public final func EnableCustomizableAppearance(val: Bool) -> Void {
    let vehicle = this.GetVehicle();
    if IsDefined(vehicle) && vehicle.GetRecordID() == t"Vehicle.v_standard2_archer_hella_player_vctest" {
        let service = GameInstance.GetScriptableServiceContainer()
            .GetService(n"VehicleCustomizerTest.KitService") as KitService;
        if IsDefined(service) {
            service.NoteLookKept(vehicle.GetCurrentAppearanceName(), val);
        }
        return;
    }
    wrappedMethod(val);
}
