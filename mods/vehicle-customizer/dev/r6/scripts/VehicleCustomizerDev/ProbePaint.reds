// Development only (vehicle-customizer/RECORD.md, 2026-11-08): how far colour can go, before building anything.
// What's probed: the game's per-part paint call (VehicleCustomizationComponent.SetupUniqueCustomization, CrystalCoat's
// unique templates), its any-colour call (SetupGenericCustomization), a colour of ours in a generated paint
// (experiments/paint/make-probe-paints.py), and whether a palette loaded through Codeware can be edited live.
// Each returns what it did, for the report; only the pictures say what the game drew.
module VehicleCustomizerDev

import VehicleCustomizer.*

public class ProbePaint extends ScriptableSystem {
    private let m_optionPaths: array<ResRef>;
    private let m_optionTokens: array<ref<ResourceToken>>;
    private let m_surface: ref<ResourceToken>;
    private let m_setup: ref<ResourceToken>;
    private let m_mesh: ref<ResourceToken>;

    // How the call is made: the game turns the default decals off first and passes a real clear coat (second round).
    private let m_decalsOff: Bool;
    private let m_realCoat: Bool;
    private let m_byName: Bool;
    private let m_coat: VehicleClearCoatOverrides;

    private static func Mask() -> ResRef {
        return r"base\\vehicles\\standard\\v_standard2_archer_hella\\entities\\meshes\\textures\\ml_v_standard2_archer_hella_ext00_masksset.mlmask";
    }

    private static func Paint(name: CName) -> ResRef {
        switch name {
            case n"magenta": return r"vehiclecustomizerdev\\paint\\door_magenta.mlsetup";
            case n"lime": return r"vehiclecustomizerdev\\paint\\door_lime.mlsetup";
            case n"primer": return r"base\\vehicles\\standard\\v_standard2_archer_hella\\entities\\meshes\\textures\\primer_red.mlsetup";
        }
        return r"";
    }

    public func Options(decalsOff: Bool, realCoat: Bool, byName: Bool) {
        this.m_decalsOff = decalsOff;
        this.m_realCoat = realCoat;
        this.m_byName = byName;
    }

    private func Component(car: ref<VehicleObject>) -> ref<VehicleCustomizationComponent> {
        if this.m_byName {
            return car.FindComponentByName(n"customization") as VehicleCustomizationComponent;
        }
        return car.GetCustomizationComponent();
    }

    // The game's own paint job's clear coat, and what its first override looks like.
    public func UseTemplate(id: TweakDBID) -> String {
        let template = TweakDBInterface.GetVehicleColorTemplateRecord(id);
        if !IsDefined(template) {
            return "no such template";
        }
        let text = TDBID.ToStringDEBUG(id) + ": ";
        let overrides = template.GlobalClearCoatOverridesHandle();
        if IsDefined(overrides) {
            this.m_coat = VehicleClearCoatOverrides.FromRecord(overrides);
            text += s"coat opacity \(this.m_coat.opacity), tint \(this.m_coat.coatTintFwd.Red) \(this.m_coat.coatTintFwd.Green) \(this.m_coat.coatTintFwd.Blue) \(this.m_coat.coatTintFwd.Alpha), specular \(this.m_coat.coatSpecularColor.Red) \(this.m_coat.coatSpecularColor.Green) \(this.m_coat.coatSpecularColor.Blue), fresnel \(this.m_coat.coatFresnelBias)";
        } else {
            text += "no coat";
        }
        let count = template.GetCustomMultilayersCount();
        text += s"; \(count) overrides";
        if count > 0 {
            let first = VehicleCustomMultilayer.FromRecord(template.GetCustomMultilayersItemHandle(0));
            text += s"; the first: \(ArraySize(first.affectedComponents)) affected, \(ArraySize(first.excludedComponents)) excluded, \(ArraySize(first.onlyForPlayerVehicleAppearances)) looks, mask \(ResRef.IsValid(first.customMlMask)), coat layers \(first.coatLayerMin) to \(first.coatLayerMax)";
        }
        return text;
    }

    private static func Entry(part: CName, paint: CName, useMask: Bool) -> VehicleCustomMultilayer {
        let entry: VehicleCustomMultilayer;
        ArrayPush(entry.affectedComponents, part);
        entry.customMlSetup = ProbePaint.Paint(paint);
        if useMask {
            entry.customMlMask = ProbePaint.Mask();
        }
        // The Hella's materials: CoatLayerMax 2.
        entry.coatLayerMin = 0.0;
        entry.coatLayerMax = 2.0;
        return entry;
    }

    private func Send(car: ref<VehicleObject>, list: array<VehicleCustomMultilayer>) -> String {
        let component = this.Component(car);
        if !IsDefined(component) {
            return "the car has no customization component";
        }
        if this.m_decalsOff {
            component.SetDefaultDecalsEnabled(false);
        }
        let empty: VehicleClearCoatOverrides;
        let parts: array<VehiclePartsClearCoatOverrides>;
        component.SetupUniqueCustomization(list, this.m_realCoat ? this.m_coat : empty, parts, true);
        return s"sent \(ArraySize(list)) override(s), decals off \(this.m_decalsOff), real coat \(this.m_realCoat), by name \(this.m_byName)";
    }

    public func Describe(car: ref<VehicleObject>) -> String {
        let record = TweakDBInterface.GetVehicleRecord(car.GetRecordID());
        let mask = record.GenericCustomizationMask();
        let named = car.FindComponentByName(n"customization") as VehicleCustomizationComponent;
        let held = car.GetCustomizationComponent();
        return s"look \(NameToString(car.GetCurrentAppearanceName())), component \(IsDefined(held)), by name \(IsDefined(named)), the same one \(held == named), game's customization enabled \(car.GetVehicleComponent().GetIsVehicleVisualCustomizationEnabled()), generic mask \(ResRef.IsValid(mask))";
    }

    public func One(car: ref<VehicleObject>, part: CName, paint: CName, useMask: Bool) -> String {
        let list: array<VehicleCustomMultilayer>;
        ArrayPush(list, ProbePaint.Entry(part, paint, useMask));
        return this.Send(car, list);
    }

    public func Two(car: ref<VehicleObject>, partA: CName, paintA: CName, partB: CName, paintB: CName) -> String {
        let list: array<VehicleCustomMultilayer>;
        ArrayPush(list, ProbePaint.Entry(partA, paintA, true));
        ArrayPush(list, ProbePaint.Entry(partB, paintB, true));
        return this.Send(car, list);
    }

    // Any colour through CrystalCoat's mask: the whole car, or (only given) just that part, every other mesh excluded.
    public func Generic(car: ref<VehicleObject>, only: CName, red: Int32, green: Int32, blue: Int32) -> String {
        let component = this.Component(car);
        if !IsDefined(component) {
            return "the car has no customization component";
        }
        let record = TweakDBInterface.GetVehicleRecord(car.GetRecordID());
        let excluded = record.ExcludedComponentsGeneric();
        if IsNameValid(only) {
            ArrayClear(excluded);
            for part in car.GetComponents() {
                let mesh = part as MeshComponent;
                if IsDefined(mesh) && !Equals(mesh.name, only) {
                    ArrayPush(excluded, mesh.name);
                }
            }
        }
        component.SetDefaultDecalsEnabled(false);
        let colour = new Color(Cast<Uint8>(red), Cast<Uint8>(green), Cast<Uint8>(blue), Cast<Uint8>(255));
        let packed = car.GetVehicleComponent().PackColorForEffect(colour);
        component.SetupGenericCustomization(excluded, record.GenericCustomizationMask(), packed, packed, true, false);
        return s"sent, \(ArraySize(excluded)) parts excluded";
    }

    // The game's script has this but nothing in it starts the effect; tried in case the colour needs it.
    public func Shader(car: ref<VehicleObject>) -> String {
        car.GetVehicleComponent().PlayVehicleVisualCustomizationShader(true, true, false);
        return "effect started";
    }

    public func Clear(car: ref<VehicleObject>) -> String {
        let component = this.Component(car);
        if !IsDefined(component) {
            return "the car has no customization component";
        }
        car.GetVehicleComponent().PlayVehicleVisualCustomizationShader(false);
        component.DisableCurrentCustomization();
        component.SetDefaultDecalsEnabled(true);
        return "cleared";
    }

    // --- resources, through Codeware ---

    public func Load() {
        let depot = GameInstance.GetResourceDepot();
        this.m_surface = depot.LoadResource(r"vehiclecustomizerdev\\paint\\vc_car_paint.mltemplate");
        this.m_setup = depot.LoadResource(ProbePaint.Paint(n"magenta"));
        this.m_mesh = depot.LoadResource(r"base\\vehicles\\standard\\v_standard2_archer_hella\\entities\\meshes\\v_standard2_archer_hella__ext01_door_fl_01.mesh");
    }

    public func Loaded() -> Bool {
        return this.m_surface.IsFinished() && this.m_setup.IsFinished() && this.m_mesh.IsFinished();
    }

    // Whether ArchiveXL's patch reached the door's mesh: its appearances, and ours among them.
    public func MeshCheck() -> String {
        let mesh = this.m_mesh.GetResource() as CMesh;
        if !IsDefined(mesh) {
            return "no mesh loaded";
        }
        let appearances = mesh.appearances;
        let probe = 0;
        let plain = 0;
        let dynamic = 0;
        for appearance in appearances {
            let name = NameToString(appearance.name);
            if StrBeginsWith(name, "vc_") {
                probe += 1;
            } else if StrBeginsWith(name, "vcp_") {
                plain += 1;
            } else if StrBeginsWith(name, "vcd_") {
                dynamic += 1;
            }
        }
        return s"door mesh: \(ArraySize(appearances)) appearances; probe \(probe), plain \(plain), dynamic \(dynamic)";
    }

    // Job "paintcheck" (RECORD.md, 2026-11-08): a catalog option's meshes as the game has them, ArchiveXL's patch included.
    public func LoadOption(cat: CName, option: CName) -> Int32 {
        this.m_optionPaths = VCData.Paths(cat, "option." + NameToString(option) + ".meshes");
        ArrayClear(this.m_optionTokens);
        let depot = GameInstance.GetResourceDepot();
        let paths = this.m_optionPaths;
        for path in paths {
            ArrayPush(this.m_optionTokens, depot.LoadResource(path));
        }
        return ArraySize(paths);
    }

    public func OptionLoaded() -> Bool {
        let tokens = this.m_optionTokens;
        for token in tokens {
            if !token.IsFinished() {
                return false;
            }
        }
        return true;
    }

    public func OptionReport() -> String {
        let text = "";
        let tokens = this.m_optionTokens;
        for token in tokens {
            let mesh = token.GetResource() as CMesh;
            if !IsDefined(mesh) {
                text += "no mesh loaded; ";
            } else {
                let appearances = mesh.appearances;
                let shop = 0;
                let first = "";
                for appearance in appearances {
                    let name = NameToString(appearance.name);
                    if StrBeginsWith(name, "vcs_") {
                        shop += 1;
                    } else if StrLen(first) == 0 {
                        first = name;
                    }
                }
                text += s"\(ArraySize(appearances)) appearances, \(shop) of ours, first of the game's \(first); ";
            }
        }
        return text;
    }

    // Every mesh on the car as it stands: name=appearance, * if it's the option's mesh, ! if the component is off.
    public func LiveParts(car: ref<VehicleObject>) -> String {
        let text = "";
        let paths = this.m_optionPaths;
        let parts = car.GetComponents();
        for part in parts {
            let mesh = part as MeshComponent;
            if IsDefined(mesh) && !StrContains(NameToString(mesh.name), "shadow") {
                let ref = mesh.mesh;
                let mark = "";
                for path in paths {
                    if ResourceAsyncRef.GetHash(ref) == ResRef.GetHash(path) {
                        mark = "*";
                    }
                }
                if !mesh.IsEnabled() {
                    mark += "!";
                }
                text += s"\(NameToString(mesh.name))\(mark)=\(NameToString(mesh.meshAppearance)); ";
            }
        }
        return text;
    }

    // A colour of our palette made another, in memory: does a car painted with it change?
    public func EditPalette(name: CName, red: Float, green: Float, blue: Float) -> String {
        let surface = this.m_surface.GetResource() as Multilayer_LayerTemplate;
        if !IsDefined(surface) {
            return "no surface loaded";
        }
        let overrides = surface.overrides;
        let colours = overrides.colorScale;
        let changed = 0;
        let i = 0;
        while i < ArraySize(colours) {
            if Equals(colours[i].n, name) {
                let entry = colours[i];
                entry.v[0] = red;
                entry.v[1] = green;
                entry.v[2] = blue;
                colours[i] = entry;
                changed += 1;
            }
            i += 1;
        }
        overrides.colorScale = colours;
        surface.overrides = overrides;
        return s"changed \(changed) palette entry(ies)";
    }
}
