// Vehicle Customizer: reading the catalogs (vehicle-customizer/RECORD.md, catalog/make-catalogs.py).
// A catalog is per entity file and lives in TweakDB under VehicleCustomizer.<catalog>, written by TweakXL from
// mod/r6/tweaks/vehiclecustomizer. Every choice in a build is an ID from it: a style (its base look), a slot,
// an option, a paint name, a kit.
module VehicleCustomizer

public abstract class VCData {
    public static func Key(cat: CName, path: String) -> TweakDBID {
        return TDBID.Create("VehicleCustomizer." + NameToString(cat) + "." + path);
    }

    public static func Names(cat: CName, path: String) -> array<CName> {
        return TweakDBInterface.GetCNameArray(VCData.Key(cat, path));
    }

    public static func Name(cat: CName, path: String) -> CName {
        return TweakDBInterface.GetCName(VCData.Key(cat, path), n"");
    }

    public static func Text(cat: CName, path: String) -> String {
        return TweakDBInterface.GetString(VCData.Key(cat, path), "");
    }

    public static func Paths(cat: CName, path: String) -> array<ResRef> {
        return TweakDBInterface.GetResRefArray(VCData.Key(cat, path));
    }

    // The shared wheel list (wheels.yaml): VehicleCustomizer.wheel.<set>.<path>.
    public static func WheelKey(set: CName, path: String) -> TweakDBID {
        return TDBID.Create("VehicleCustomizer.wheel." + NameToString(set) + "." + path);
    }

    public static func Catalogs() -> array<CName> {
        return TweakDBInterface.GetCNameArray(t"VehicleCustomizer.catalogs");
    }

    public static func Records(cat: CName) -> array<TweakDBID> {
        return TweakDBInterface.GetForeignKeyArray(VCData.Key(cat, "records"));
    }

    public static func Pool(cat: CName) -> array<TweakDBID> {
        return TweakDBInterface.GetForeignKeyArray(VCData.Key(cat, "pool"));
    }

    // A look without the twin suffix the engine adds: archer_hella__basic_player_01__vc_b -> ..._player_01.
    public static func BaseLook(look: String) -> String {
        if StrEndsWith(look, "__vc_a") || StrEndsWith(look, "__vc_b") {
            return StrLeft(look, StrLen(look) - 6);
        }
        return look;
    }

    // The part that fills a slot's corner in a look: rows "<slot>|<corner>|<part name>".
    public static func PartOf(cat: CName, look: String, slot: CName, corner: CName) -> CName {
        let want = NameToString(slot) + "|" + NameToString(corner) + "|";
        for row in VCData.Names(cat, "look." + look + ".parts") {
            let text = NameToString(row);
            if StrBeginsWith(text, want) {
                return StringToName(StrRight(text, StrLen(text) - StrLen(want)));
            }
        }
        return n"";
    }

    // Whether a list of names from the catalog has this one, compared as text: the first suite run (2026-11-06)
    // found a style never matched when compared as names, while the text comparisons of PartOf all did.
    // Whether a catalog option can wear a paint: one of its mesh's own, or one of the shop's colours if its meshes all have
    // them (shop-paints.yaml, written by experiments/paint/make-paints.py).
    public static func Offers(cat: CName, option: CName, offered: array<CName>, paint: CName) -> Bool {
        if VCData.Has(offered, paint) {
            return true;
        }
        return StrBeginsWith(NameToString(paint), "vcs_")
            && TweakDBInterface.GetBool(VCData.Key(cat, "option." + NameToString(option) + ".shopPaint"), false);
    }

    public static func Has(list: array<CName>, name: CName) -> Bool {
        let want = NameToString(name);
        let i = 0;
        while i < ArraySize(list) {
            if Equals(NameToString(list[i]), want) {
                return true;
            }
            i += 1;
        }
        return false;
    }

    // The style a look belongs to, and the option that style has in a slot ("<slot>=<option>").
    public static func StyleOf(cat: CName, look: String) -> CName {
        let base = StringToName(VCData.BaseLook(look));
        let styles = VCData.Names(cat, "styles");
        let i = 0;
        while i < ArraySize(styles) {
            if VCData.Has(VCData.Names(cat, "style." + NameToString(styles[i]) + ".looks"), base) {
                return styles[i];
            }
            i += 1;
        }
        return n"";
    }

    public static func StyleOption(cat: CName, style: CName, slot: CName) -> CName {
        let want = NameToString(slot) + "=";
        let rows = VCData.Names(cat, "style." + NameToString(style) + ".options");
        let i = 0;
        while i < ArraySize(rows) {
            let text = NameToString(rows[i]);
            if StrBeginsWith(text, want) {
                return StringToName(StrRight(text, StrLen(text) - StrLen(want)));
            }
            i += 1;
        }
        return n"";
    }
}
