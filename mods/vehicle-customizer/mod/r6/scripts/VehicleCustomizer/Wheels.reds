// Vehicle Customizer: the rims and tires a car can wear, for the tool and the F7 screen alike (UX.md, "Where
// options live", 2026-11-07). Rims and tires are chosen apart from the shared wheel list (wheels.yaml): each mesh once,
// a set's id naming its rim or its tire; this car's own come first (its catalog's ownRims and ownTires), then every
// other vehicle's of its kind (car or bike), in the list's order (by the car each comes from).
module VehicleCustomizer

public abstract class VCWheels {
    // n"" first (the car's own), then this car's own, then the rest.
    public static func List(cat: CName, tires: Bool) -> array<CName> {
        let out: array<CName>;
        ArrayPush(out, n"");
        let kind = VCData.Name(cat, "wheelKind");
        let mine = VCData.Names(cat, tires ? "ownTires" : "ownRims");
        for id in mine {
            ArrayPush(out, id);
        }
        let all = TweakDBInterface.GetCNameArray(TDBID.Create("VehicleCustomizer." + (tires ? "tires." : "rims.")
            + (Equals(kind, n"bike") ? "bike" : "car")));
        for id in all {
            if !ArrayContains(mine, id) {
                ArrayPush(out, id);
            }
        }
        return out;
    }

    public static func Label(set: CName, tire: Bool) -> String {
        if !IsNameValid(set) {
            return tire ? "Car's own tires" : "Car's own rims";
        }
        return TweakDBInterface.GetString(VCData.WheelKey(set, tire ? "tireLabel" : "rimLabel"), NameToString(set));
    }
}
