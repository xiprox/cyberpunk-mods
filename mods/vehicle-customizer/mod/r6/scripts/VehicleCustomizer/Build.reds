// Vehicle Customizer: one car's build, as catalog IDs (vehicle-customizer/RECORD.md, 2026-11-06).
// The layers, bottom to top: the look (a style's base look or one of its factory paints), a whole-car paint, a
// part option per slot with an optional paint of its own, and add-on kits with an offset each. Written as a
// short text so it can be saved with the game and, later, sent to co-op partners in NightCoop's entity state
// (up to 1,024 bytes):
//   look=<look>;paint=<paint>;slot=<slot>:<option>:<paint>;...;kit=<kit>:<x>:<y>:<z>:<yaw>
// and rims and tires from the shared wheel list, chosen apart (user, 2026-11-07), per axle or both, a set's id
// naming its rim or its tire, with how big the wheels sit, in percent of the car's own:
//   rims=<set>;tires=<set>  or  rims@f=<set>;rims@b=<set>;tires@f=...;fit@f=<size>:<width>;fit@b=<size>:<width>
// An older build's wheels=<set> (a rim with its own tire) reads as that set's rim and tire.
module VehicleCustomizer

public class VCBuild {
    public let look: CName;
    public let paint: CName; // the whole car's paint, on every part that offers it
    public let rimFront: CName; // a set's rim from the shared list, or none: the car's own rim
    public let rimBack: CName;
    public let tireFront: CName; // a set's tire from the shared list, or none: the car's own tire
    public let tireBack: CName;
    public let fitFront: Vector4; // x size, y width, in percent of the car's own wheels; 0 means 100
    public let fitBack: Vector4;
    public let wheelPaintFront: CName; // the rims' paint, on a set's rims or the car's own: wheelpaint=, @f=, @b=
    public let wheelPaintBack: CName;
    public let slots: array<CName>;
    public let options: array<CName>;
    public let paints: array<CName>;
    public let kits: array<CName>;
    public let kitOffsets: array<Vector4>; // x, y, z in metres; w is the turn about z (yaw) in degrees
    public let kitTurns: array<Vector4>; // x pitch (about x), y roll (about y), degrees; with kits
    // Single parts of a kit moved on their own (the user expects that wanted more than moving a kit whole):
    //   part=<kit>:<index>:<x>:<y>:<z>:<yaw>:<pitch>:<roll>, only for parts moved.
    public let partKits: array<CName>;
    public let partIndexes: array<Int32>;
    public let partMoves: array<Vector4>; // x, y, z, w yaw
    public let partTurns: array<Vector4>; // x pitch, y roll

    public static func Parse(text: String) -> ref<VCBuild> {
        let build = new VCBuild();
        for field in StrSplit(text, ";", false) {
            let parts = StrSplit(field, ":", true);
            if StrBeginsWith(field, "look=") {
                build.look = StringToName(StrRight(field, StrLen(field) - 5));
            } else if StrBeginsWith(field, "paint=") {
                build.paint = StringToName(StrRight(field, StrLen(field) - 6));
            } else if StrBeginsWith(field, "rims=") {
                build.rimFront = StringToName(StrRight(field, StrLen(field) - 5));
                build.rimBack = build.rimFront;
            } else if StrBeginsWith(field, "rims@f=") {
                build.rimFront = StringToName(StrRight(field, StrLen(field) - 7));
            } else if StrBeginsWith(field, "rims@b=") {
                build.rimBack = StringToName(StrRight(field, StrLen(field) - 7));
            } else if StrBeginsWith(field, "tires=") {
                build.tireFront = StringToName(StrRight(field, StrLen(field) - 6));
                build.tireBack = build.tireFront;
            } else if StrBeginsWith(field, "tires@f=") {
                build.tireFront = StringToName(StrRight(field, StrLen(field) - 8));
            } else if StrBeginsWith(field, "tires@b=") {
                build.tireBack = StringToName(StrRight(field, StrLen(field) - 8));
            } else if StrBeginsWith(field, "wheels=") {
                build.rimFront = StringToName(StrRight(field, StrLen(field) - 7));
                build.rimBack = build.rimFront;
                build.tireFront = build.rimFront;
                build.tireBack = build.rimFront;
            } else if StrBeginsWith(field, "wheels@f=") {
                build.rimFront = StringToName(StrRight(field, StrLen(field) - 9));
                build.tireFront = build.rimFront;
            } else if StrBeginsWith(field, "wheels@b=") {
                build.rimBack = StringToName(StrRight(field, StrLen(field) - 9));
                build.tireBack = build.rimBack;
            } else if StrBeginsWith(field, "wheelpaint=") {
                build.wheelPaintFront = StringToName(StrRight(field, StrLen(field) - 11));
                build.wheelPaintBack = build.wheelPaintFront;
            } else if StrBeginsWith(field, "wheelpaint@f=") {
                build.wheelPaintFront = StringToName(StrRight(field, StrLen(field) - 13));
            } else if StrBeginsWith(field, "wheelpaint@b=") {
                build.wheelPaintBack = StringToName(StrRight(field, StrLen(field) - 13));
            } else if StrBeginsWith(field, "fit@f=") && ArraySize(parts) >= 2 {
                build.fitFront = VCBuild.ParseFit(parts);
            } else if StrBeginsWith(field, "fit@b=") && ArraySize(parts) >= 2 {
                build.fitBack = VCBuild.ParseFit(parts);
            } else if StrBeginsWith(field, "slot=") && ArraySize(parts) >= 2 {
                ArrayPush(build.slots, StringToName(StrRight(parts[0], StrLen(parts[0]) - 5)));
                ArrayPush(build.options, StringToName(parts[1]));
                ArrayPush(build.paints, ArraySize(parts) >= 3 ? StringToName(parts[2]) : n"");
            } else if StrBeginsWith(field, "kit=") && ArraySize(parts) >= 1 {
                ArrayPush(build.kits, StringToName(StrRight(parts[0], StrLen(parts[0]) - 4)));
                // Set every time: a "let" in a loop keeps the last pass's value (third suite run, 2026-11-06,
                // gave a kit without numbers the kit before it's offset).
                let offset = new Vector4(0.0, 0.0, 0.0, 0.0);
                if ArraySize(parts) >= 5 {
                    offset = new Vector4(StringToFloat(parts[1]), StringToFloat(parts[2]), StringToFloat(parts[3]),
                        StringToFloat(parts[4]));
                }
                ArrayPush(build.kitOffsets, offset);
                let turn = new Vector4(0.0, 0.0, 0.0, 0.0);
                if ArraySize(parts) >= 7 {
                    turn = new Vector4(StringToFloat(parts[5]), StringToFloat(parts[6]), 0.0, 0.0);
                }
                ArrayPush(build.kitTurns, turn);
            } else if StrBeginsWith(field, "part=") && ArraySize(parts) >= 8 {
                ArrayPush(build.partKits, StringToName(StrRight(parts[0], StrLen(parts[0]) - 5)));
                ArrayPush(build.partIndexes, StringToInt(parts[1]));
                ArrayPush(build.partMoves, new Vector4(StringToFloat(parts[2]), StringToFloat(parts[3]),
                    StringToFloat(parts[4]), StringToFloat(parts[5])));
                ArrayPush(build.partTurns, new Vector4(StringToFloat(parts[6]), StringToFloat(parts[7]), 0.0, 0.0));
            }
        }
        return build;
    }

    // ";<what>=<set>" when both axles have it, else ";<what>@f=" and ";<what>@b=" for each that has one.
    private static func AxleText(what: String, front: CName, back: CName) -> String {
        if IsNameValid(front) && Equals(front, back) {
            return ";" + what + "=" + NameToString(front);
        }
        let text = "";
        if IsNameValid(front) {
            text += ";" + what + "@f=" + NameToString(front);
        }
        if IsNameValid(back) {
            text += ";" + what + "@b=" + NameToString(back);
        }
        return text;
    }

    public func ToText() -> String {
        let text = "look=" + NameToString(this.look);
        if IsNameValid(this.paint) {
            text += ";paint=" + NameToString(this.paint);
        }
        text += VCBuild.AxleText("rims", this.rimFront, this.rimBack);
        text += VCBuild.AxleText("tires", this.tireFront, this.tireBack);
        if IsNameValid(this.wheelPaintFront) && Equals(this.wheelPaintFront, this.wheelPaintBack) {
            text += ";wheelpaint=" + NameToString(this.wheelPaintFront);
        } else {
            if IsNameValid(this.wheelPaintFront) {
                text += ";wheelpaint@f=" + NameToString(this.wheelPaintFront);
            }
            if IsNameValid(this.wheelPaintBack) {
                text += ";wheelpaint@b=" + NameToString(this.wheelPaintBack);
            }
        }
        if VCBuild.Fitted(this.fitFront) {
            text += ";fit@f=" + VCBuild.FitText(this.fitFront);
        }
        if VCBuild.Fitted(this.fitBack) {
            text += ";fit@b=" + VCBuild.FitText(this.fitBack);
        }
        let i = 0;
        while i < ArraySize(this.slots) {
            text += ";slot=" + NameToString(this.slots[i]) + ":" + NameToString(this.options[i]) + ":"
                + (IsNameValid(this.paints[i]) ? NameToString(this.paints[i]) : "");
            i += 1;
        }
        i = 0;
        while i < ArraySize(this.kits) {
            let o = this.kitOffsets[i];
            text += ";kit=" + NameToString(this.kits[i]) + ":" + FloatToStringPrec(o.X, 3) + ":"
                + FloatToStringPrec(o.Y, 3) + ":" + FloatToStringPrec(o.Z, 3) + ":" + FloatToStringPrec(o.W, 1);
            let t = i < ArraySize(this.kitTurns) ? this.kitTurns[i] : new Vector4(0.0, 0.0, 0.0, 0.0);
            if AbsF(t.X) > 0.05 || AbsF(t.Y) > 0.05 {
                text += ":" + FloatToStringPrec(t.X, 1) + ":" + FloatToStringPrec(t.Y, 1);
            }
            i += 1;
        }
        i = 0;
        while i < ArraySize(this.partKits) {
            let m = this.partMoves[i];
            let t = this.partTurns[i];
            text += ";part=" + NameToString(this.partKits[i]) + ":" + IntToString(this.partIndexes[i]) + ":"
                + FloatToStringPrec(m.X, 3) + ":" + FloatToStringPrec(m.Y, 3) + ":" + FloatToStringPrec(m.Z, 3) + ":"
                + FloatToStringPrec(m.W, 1) + ":" + FloatToStringPrec(t.X, 1) + ":" + FloatToStringPrec(t.Y, 1);
            i += 1;
        }
        return text;
    }

    public func KitTurn(k: Int32) -> Vector4 {
        return k >= 0 && k < ArraySize(this.kitTurns) ? this.kitTurns[k] : new Vector4(0.0, 0.0, 0.0, 0.0);
    }

    public func PartIndex(kit: CName, part: Int32) -> Int32 {
        let i = 0;
        while i < ArraySize(this.partKits) {
            if Equals(this.partKits[i], kit) && this.partIndexes[i] == part {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    public func PartMove(kit: CName, part: Int32) -> Vector4 {
        let i = this.PartIndex(kit, part);
        return i >= 0 ? this.partMoves[i] : new Vector4(0.0, 0.0, 0.0, 0.0);
    }

    public func PartTurn(kit: CName, part: Int32) -> Vector4 {
        let i = this.PartIndex(kit, part);
        return i >= 0 ? this.partTurns[i] : new Vector4(0.0, 0.0, 0.0, 0.0);
    }

    // Moves a kit by a step: the whole kit (part -1) or one of its parts. move: x, y, z in metres and w the yaw;
    // turn: x pitch, y roll, in degrees.
    public func Nudge(kit: CName, part: Int32, move: Vector4, turn: Vector4) {
        if part < 0 {
            let k = this.KitIndex(kit);
            if k < 0 {
                return;
            }
            let o = this.kitOffsets[k];
            this.kitOffsets[k] = new Vector4(o.X + move.X, o.Y + move.Y, o.Z + move.Z, o.W + move.W);
            while ArraySize(this.kitTurns) < ArraySize(this.kits) {
                ArrayPush(this.kitTurns, new Vector4(0.0, 0.0, 0.0, 0.0));
            }
            let t = this.kitTurns[k];
            this.kitTurns[k] = new Vector4(t.X + turn.X, t.Y + turn.Y, 0.0, 0.0);
            return;
        }
        let i = this.PartIndex(kit, part);
        if i < 0 {
            ArrayPush(this.partKits, kit);
            ArrayPush(this.partIndexes, part);
            ArrayPush(this.partMoves, new Vector4(0.0, 0.0, 0.0, 0.0));
            ArrayPush(this.partTurns, new Vector4(0.0, 0.0, 0.0, 0.0));
            i = ArraySize(this.partKits) - 1;
        }
        let m = this.partMoves[i];
        this.partMoves[i] = new Vector4(m.X + move.X, m.Y + move.Y, m.Z + move.Z, m.W + move.W);
        let t = this.partTurns[i];
        this.partTurns[i] = new Vector4(t.X + turn.X, t.Y + turn.Y, 0.0, 0.0);
    }

    // Puts a kit, or one of its parts, back where it came.
    public func ResetKitMoves(kit: CName, part: Int32) {
        if part < 0 {
            let k = this.KitIndex(kit);
            if k >= 0 {
                this.kitOffsets[k] = new Vector4(0.0, 0.0, 0.0, 0.0);
                if k < ArraySize(this.kitTurns) {
                    this.kitTurns[k] = new Vector4(0.0, 0.0, 0.0, 0.0);
                }
            }
        }
        let i = ArraySize(this.partKits) - 1;
        while i >= 0 {
            if Equals(this.partKits[i], kit) && (part < 0 || this.partIndexes[i] == part) {
                ArrayErase(this.partKits, i);
                ArrayErase(this.partIndexes, i);
                ArrayErase(this.partMoves, i);
                ArrayErase(this.partTurns, i);
            }
            i -= 1;
        }
    }

    // A fit other than the car's own size: 0 or 100 in any means as the car's own. x the wheel's size, y the tire's
    // width, z the rim's width (user, 2026-11-07: a width for each, to match one to the other).
    public static func Fitted(fit: Vector4) -> Bool {
        let size = fit.X <= 0.0 ? 100.0 : fit.X;
        let width = fit.Y <= 0.0 ? 100.0 : fit.Y;
        let rimWidth = fit.Z <= 0.0 ? 100.0 : fit.Z;
        return AbsF(size - 100.0) > 0.5 || AbsF(width - 100.0) > 0.5 || AbsF(rimWidth - 100.0) > 0.5;
    }

    // Size, tire width and rim width as multipliers (1.0 is the car's own).
    public static func FitScale(fit: Vector4) -> Vector4 {
        return new Vector4(fit.X <= 0.0 ? 1.0 : fit.X / 100.0, fit.Y <= 0.0 ? 1.0 : fit.Y / 100.0,
            fit.Z <= 0.0 ? 1.0 : fit.Z / 100.0, 0.0);
    }

    // The fit's text: "size:width", and ":rim width" when the rim's isn't its own (older builds have two numbers).
    private static func FitText(fit: Vector4) -> String {
        let text = FloatToStringPrec(fit.X <= 0.0 ? 100.0 : fit.X, 0) + ":" + FloatToStringPrec(fit.Y <= 0.0 ? 100.0 : fit.Y, 0);
        if fit.Z > 0.0 && AbsF(fit.Z - 100.0) > 0.5 {
            text += ":" + FloatToStringPrec(fit.Z, 0);
        }
        return text;
    }

    private static func ParseFit(parts: array<String>) -> Vector4 {
        let rimWidth = ArraySize(parts) >= 3 ? StringToFloat(parts[2]) : 0.0;
        return new Vector4(StringToFloat(StrRight(parts[0], StrLen(parts[0]) - 6)), StringToFloat(parts[1]), rimWidth, 0.0);
    }

    public func SlotIndex(slot: CName) -> Int32 {
        let i = 0;
        while i < ArraySize(this.slots) {
            if Equals(this.slots[i], slot) {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    public func SetOption(slot: CName, option: CName, paint: CName) {
        let i = this.SlotIndex(slot);
        if i < 0 {
            ArrayPush(this.slots, slot);
            ArrayPush(this.options, option);
            ArrayPush(this.paints, paint);
        } else {
            this.options[i] = option;
            this.paints[i] = paint;
        }
    }

    public func ClearSlot(slot: CName) {
        let i = this.SlotIndex(slot);
        if i >= 0 {
            ArrayErase(this.slots, i);
            ArrayErase(this.options, i);
            ArrayErase(this.paints, i);
        }
    }

    public func KitIndex(kit: CName) -> Int32 {
        let i = 0;
        while i < ArraySize(this.kits) {
            if Equals(this.kits[i], kit) {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    public func ToggleKit(kit: CName) -> Bool {
        let i = this.KitIndex(kit);
        if i >= 0 {
            this.ResetKitMoves(kit, -1);
            ArrayErase(this.kits, i);
            ArrayErase(this.kitOffsets, i);
            if i < ArraySize(this.kitTurns) {
                ArrayErase(this.kitTurns, i);
            }
            return false;
        }
        while ArraySize(this.kitTurns) < ArraySize(this.kits) {
            ArrayPush(this.kitTurns, new Vector4(0.0, 0.0, 0.0, 0.0));
        }
        ArrayPush(this.kits, kit);
        ArrayPush(this.kitOffsets, new Vector4(0.0, 0.0, 0.0, 0.0));
        ArrayPush(this.kitTurns, new Vector4(0.0, 0.0, 0.0, 0.0));
        return true;
    }
}
