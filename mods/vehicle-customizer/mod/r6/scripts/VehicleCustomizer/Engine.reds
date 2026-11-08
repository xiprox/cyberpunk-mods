// Vehicle Customizer: the engine (vehicle-customizer/RECORD.md).
// It keeps every customizable car's build with the savegame, and puts the build on as the game builds the car:
// when it's called (the builder carries the car's record) and when it changes look. A rebuild in place is a
// switch between a look's twins, <look>__vc_a and <look>__vc_b, which the mod's ArchiveXL archive adds to
// every catalog's entity file; such a build carries neither record nor entity, so the engine notes which car
// it asked to rebuild and in which look. The game's own reset of a car to its record's look when the player
// gets in (CrystalCoat's EnableCustomizableAppearance) is refused for our cars.
module VehicleCustomizer

public class VCEngine extends ScriptableSystem {
    // Saved with the game: each record's build text, in pieces of up to 200 characters, in order. The text is kept
    // as names, since string arrays can't be saved, and a name holds only about 255 characters (third suite run,
    // 2026-11-06: a build of 4 slots and 3 kits was cut there).
    private persistent let m_buildRecords: array<TweakDBID>;
    private persistent let m_buildTexts: array<CName>;

    // Our records and their catalogs, from TweakDB: the pool copies the shop sells, and V's own cars (records a
    // catalog lists that the game's garage list has: the mod replaces CrystalCoat, user, 2026-11-06). Traffic and
    // story cars stay as the game makes them. A car of ours keeps CrystalCoat until it has a build.
    private let m_records: array<TweakDBID>;
    private let m_recordCatalogs: array<CName>;
    private let m_poolRecords: array<TweakDBID>;
    // Rebuilds the engine asked for: the look being built, and the record and entity it's for.
    private let m_pendingLooks: array<CName>;
    private let m_pendingRecords: array<TweakDBID>;
    private let m_pendingEntities: array<EntityID>;
    // In a co-op session: each record's build for everyone, from NightCoop's shared state (see "co-op" below), and
    // the records whose saved build this machine put in this session.
    private let m_sessionRecords: array<TweakDBID>;
    private let m_sessionTexts: array<String>;
    private let m_seeded: array<TweakDBID>;
    // NightCoop as of its last frame (VCCoop.OnFrame), for code that doesn't run on the game thread, and the writes
    // to the session's state waiting for the next frame ("" removes a key) (see "co-op").
    private let m_inSession: Bool;
    private let m_peerNumbers: array<Int32>;
    private let m_peerNames: array<String>;
    private let m_partnerLed: array<EntityID>;
    private let m_outKeys: array<String>;
    private let m_outValues: array<String>;
    private let m_outFailed: array<String>;
    // Records whose build went on as the game built them by record, not yet seen attaching.
    private let m_builtRecords: array<TweakDBID>;
    // When each car was last rebuilt, and the cars waiting for their next one (see Rebuild).
    private let m_rebuiltEntities: array<EntityID>;
    private let m_rebuiltTimes: array<Float>;
    private let m_waitingEntities: array<EntityID>;
    // The last entity seen for each of our records, for the dev panel and tests.
    private let m_seenRecords: array<TweakDBID>;
    private let m_seenEntities: array<EntityID>;
    private let m_note: String;
    private let m_log: array<String>;
    private let m_logCount: Int32;
    private let m_builds: Int32;

    public static func Get(game: GameInstance) -> ref<VCEngine> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(n"VehicleCustomizer.VCEngine") as VCEngine;
    }

    // Builds are watched by each catalog's entity file (EntityTarget.Template), never by look file
    // (EntityTarget.Definition): Codeware 1.21.2's check for a look-file target walks a build's custom appearances
    // without checking that each has its look file, and getting into a car whose paint is being set (CrystalCoat,
    // and NightCoop's car paint on the host) makes such a build. It crashed Bossun's game twice on getting into a
    // car, at Codeware.dll+0x134824 (co-op test, 2026-11-06 evening). The template check reads the build's entity
    // file, which every build has.
    private func OnAttach() {
        let templates: array<ResRef>;
        let cats = VCData.Catalogs();
        let garage = TweakDBInterface.GetForeignKeyArray(t"Vehicle.vehicle_list.list");
        let own = 0;
        for cat in cats {
            let pool = VCData.Pool(cat);
            for record in pool {
                ArrayPush(this.m_records, record);
                ArrayPush(this.m_recordCatalogs, cat);
                ArrayPush(this.m_poolRecords, record);
            }
            let records = VCData.Records(cat);
            for record in records {
                if !ArrayContains(pool, record) && ArrayContains(garage, record) && !ArrayContains(this.m_records, record) {
                    ArrayPush(this.m_records, record);
                    ArrayPush(this.m_recordCatalogs, cat);
                    own += 1;
                }
            }
            let entity = TweakDBInterface.GetResRef(VCData.Key(cat, "entity"), r"");
            if ResRef.IsValid(entity) && !ArrayContains(templates, entity) {
                ArrayPush(templates, entity);
            }
        }
        let handler = GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Extract", this, n"OnExtract");
        for template in templates {
            handler.AddTarget(EntityTarget.Template(template));
        }
        this.Note(s"ready: \(ArraySize(cats)) catalogs, \(ArraySize(this.m_poolRecords)) pool copies and \(own) of V's own cars, \(ArraySize(templates)) entity files watched");
    }

    // What the engine did, newest last, for the dev panel and tests; also in the redscript log.
    private func Note(text: String) {
        this.m_note = text;
        ArrayPush(this.m_log, text);
        if ArraySize(this.m_log) > 60 {
            ArrayErase(this.m_log, 0);
        }
        this.m_logCount += 1;
        FTLog("[VehicleCustomizer] " + text);
        VCLiveLog(text);
    }

    // A line in the engine's log from elsewhere in the mod (the screen's buying and bringing).
    public func Log(text: String) {
        this.Note(text);
    }

    public func GetLogCount() -> Int32 {
        return this.m_logCount;
    }

    // Line n of everything noted since the game started, counting from 0, or "" once it's gone from the list.
    public func GetLogLine(n: Int32) -> String {
        let i = n - (this.m_logCount - ArraySize(this.m_log));
        return i >= 0 && i < ArraySize(this.m_log) ? this.m_log[i] : "";
    }

    private func OnDetach() {
        GameInstance.GetCallbackSystem().UnregisterCallback(n"Entity/Extract", this);
    }

    // --- what is ours ---

    public func CatalogOf(record: TweakDBID) -> CName {
        let i = 0;
        while i < ArraySize(this.m_records) {
            if this.m_records[i] == record {
                return this.m_recordCatalogs[i];
            }
            i += 1;
        }
        return n"";
    }

    public func IsOurs(record: TweakDBID) -> Bool {
        return IsNameValid(this.CatalogOf(record));
    }

    // A copy the shop sells, not one of V's own cars.
    public func IsPoolCopy(record: TweakDBID) -> Bool {
        return ArrayContains(this.m_poolRecords, record);
    }

    // Whether this player owns a car of ours: a shop copy they bought (buying saves its build), or one of V's own
    // cars that's in their garage.
    public func Owns(record: TweakDBID) -> Bool {
        if this.IsPoolCopy(record) {
            return StrLen(this.GetBuildText(record)) > 0;
        }
        return this.IsOurs(record) && this.IsUnlocked(record);
    }


    // --- builds, saved with the game ---

    public func GetBuildText(record: TweakDBID) -> String {
        let text = "";
        let i = 0;
        while i < ArraySize(this.m_buildRecords) {
            if this.m_buildRecords[i] == record {
                text += NameToString(this.m_buildTexts[i]);
            }
            i += 1;
        }
        return text;
    }

    public func GetBuild(record: TweakDBID) -> ref<VCBuild> {
        return VCBuild.Parse(this.GetBuildText(record));
    }

    // --- co-op: one build per car for the whole session (Coop.reds) ---
    // In a session every car of ours has one build, the same for everyone, in NightCoop's shared state: one key per
    // record, since one record is one car in a session. The host keeps it, late joiners get all of it, and the end
    // of a session clears it (nightcoop-sdk/docs/api.md); nothing of it is saved. A car wears the session's build
    // for its record if there is one, else our saved one, so a car is built right the moment it appears, whoever
    // drives it. A change goes in as "c|<build>", and every player who owns the car keeps it in their save, whoever
    // made it: a car two players own is one car with one look, and both take that look home (user, 2026-11-07). An
    // owner's car that comes out puts its saved build in as "s|<build>" when the session has none for it; nobody
    // keeps that one, so only a change replaces another owner's own build of the car.
    // This replaced entity state set by the car's leader (2026-11-06 night): NightCoop dropped it for a car it
    // didn't sync yet, it had to be sent again whenever a car changed hands, and it held only 1,024 bytes.

    // The build a car of this record wears: the session's, else ours, saved.
    public func WornText(record: TweakDBID) -> String {
        let i = ArrayFindFirst(this.m_sessionRecords, record);
        return i >= 0 ? this.m_sessionTexts[i] : this.GetBuildText(record);
    }

    public func BuildTextOf(vehicle: ref<VehicleObject>) -> String {
        return this.WornText(vehicle.GetRecordID());
    }

    public func HasSessionBuild(record: TweakDBID) -> Bool {
        return ArrayContains(this.m_sessionRecords, record);
    }

    // A record's key in the session's state: its name without "Vehicle.", since keys hold 64 bytes and the longest
    // name of ours is 63 with it.
    public static func SessionKey(record: TweakDBID) -> String {
        let name = TDBID.ToStringDEBUG(record);
        return StrBeginsWith(name, "Vehicle.") ? StrRight(name, StrLen(name) - 8) : name;
    }

    private func SetSessionText(record: TweakDBID, text: String) {
        let i = ArrayFindFirst(this.m_sessionRecords, record);
        if StrLen(text) == 0 {
            if i >= 0 {
                ArrayErase(this.m_sessionRecords, i);
                ArrayErase(this.m_sessionTexts, i);
            }
        } else if i >= 0 {
            this.m_sessionTexts[i] = text;
        } else {
            ArrayPush(this.m_sessionRecords, record);
            ArrayPush(this.m_sessionTexts, text);
        }
    }

    // A key of the session's state changed, from NightCoop (Coop.reds): "c|<build>" a change, "s|<build>" an
    // owner's saved build, "" the key is gone.
    public func OnSessionState(key: String, value: String, from: Int32) {
        let record = TDBID.Create("Vehicle." + key);
        if !this.IsOurs(record) {
            return;
        }
        let text = StrLen(value) > 2 ? StrRight(value, StrLen(value) - 2) : "";
        this.PutSessionBuild(record, text, StrBeginsWith(value, "c|"), from);
    }

    // The session's build for a record: worn by its car here, and kept in our save if it's a change to a car we
    // own. The car is rebuilt unless it wears it already (our own change coming back from the host). Public for the
    // dev suite, which plays a partner's build arriving.
    public func PutSessionBuild(record: TweakDBID, text: String, change: Bool, from: Int32) {
        let vehicle = this.VehicleOf(record);
        let before = this.WornText(record);
        this.SetSessionText(record, text);
        let kept = change && StrLen(text) > 0 && this.Owns(record);
        if kept {
            this.SetBuildText(record, text);
        }
        let rebuild = IsDefined(vehicle) && !Equals(before, this.WornText(record));
        this.Note(s"session build for \(VCEngine.SessionKey(record)) from peer \(from): "
            + (StrLen(text) == 0 ? "gone" : change ? "a change" : "an owner's build")
            + (kept ? ", kept in our save" : "") + (rebuild ? ", rebuilding the car" : IsDefined(vehicle) ? ", on already" : ""));
        if rebuild {
            this.Rebuild(vehicle);
        }
    }

    // A change: out of a session the player's own, saved; in one, the session's build for everyone. Our car shows it
    // at once; it goes into our save now if we own the car, and again for every owner when the host's word comes.
    // The write itself waits for NightCoop's next frame (PutState).
    private func Keep(record: TweakDBID, text: String) {
        if !this.m_inSession {
            this.SetBuildText(record, text);
            return;
        }
        this.SetSessionText(record, text);
        if this.Owns(record) {
            this.SetBuildText(record, text);
        }
        this.PutState(VCEngine.SessionKey(record), "c|" + text);
    }

    // --- co-op: calls into NightCoop, on the game thread only ---
    // NightCoop refuses most of its SDK's calls from any thread but the game's ("a mod called a game-thread function
    // of the SDK from another thread — refused", answered as -2, not now). Callbacks of the game's DelaySystem and
    // the screen's clicks and refreshes don't run on it: tonight's first session test had 96 refusals in half a
    // minute, all ours, and Bossun's game logged over 1,000 on 2026-11-06, among them the moment his Cortes share
    // was answered -2 (14:55:12) (2026-11-07). So NightCoop is called only from its own frame (VCCoop.OnFrame,
    // NightCoopSdk.ListenFrame) and events (Listen), both on the game thread; everything else reads what the
    // frame last saw and leaves its writes here for the next frame.

    public func InSession() -> Bool {
        return this.m_inSession;
    }

    public func PartnerCount() -> Int32 {
        return ArraySize(this.m_peerNumbers);
    }

    public func PeerName(peer: Int32) -> String {
        let i = ArrayFindFirst(this.m_peerNumbers, peer);
        return i >= 0 ? this.m_peerNames[i] : "";
    }

    // Whether a partner leads a car now (drives it, or it's theirs and nobody drives), as of the last second.
    public func PartnerLeads(vehicle: ref<VehicleObject>) -> Bool {
        return ArrayContains(this.m_partnerLed, vehicle.GetEntityID());
    }

    // A write to the session's state for the next frame; a later one for the same key replaces it.
    public func PutState(key: String, value: String) {
        let i = ArrayFindFirst(this.m_outKeys, key);
        if i >= 0 {
            this.m_outValues[i] = value;
        } else {
            ArrayPush(this.m_outKeys, key);
            ArrayPush(this.m_outValues, value);
        }
    }

    // NightCoop's frame, every frame (VCCoop): what it says now, and the writes waiting. A write it answers "not now"
    // (a guest whose host hasn't answered the mods check yet) stays for the next frame, noted once.
    public func OnCoopFrame(inSession: Bool) {
        this.m_inSession = inSession;
        if !inSession {
            // Never out of a session: there NightCoop keeps state locally, and a host would start its next
            // session with it.
            ArrayClear(this.m_outKeys);
            ArrayClear(this.m_outValues);
            return;
        }
        let i = ArraySize(this.m_outKeys) - 1;
        while i >= 0 {
            let key = this.m_outKeys[i];
            let answer = VCPutState(key, this.m_outValues[i]);
            if answer == -2 {
                if !ArrayContains(this.m_outFailed, key) {
                    ArrayPush(this.m_outFailed, key);
                    this.Note(s"the session's state for \(key): NightCoop says not now; trying each frame");
                }
            } else {
                if answer < 0 {
                    this.Note(s"the session's state for \(key) was refused (answer \(answer)): it shows here only");
                }
                ArrayRemove(this.m_outFailed, key);
                ArrayErase(this.m_outKeys, i);
                ArrayErase(this.m_outValues, i);
            }
            i -= 1;
        }
    }

    // Once a second from NightCoop's frame, in a session: the partners' names, and which cars of ours partners lead.
    public func OnCoopSecond(peers: array<Int32>, names: array<String>) {
        this.m_peerNumbers = peers;
        this.m_peerNames = names;
        let led: array<EntityID>;
        for entity in this.m_seenEntities {
            let vehicle = GameInstance.FindEntityByID(this.GetGameInstance(), entity) as VehicleObject;
            if IsDefined(vehicle) && !VCLeads(vehicle) {
                ArrayPush(led, entity);
            }
        }
        this.m_partnerLed = led;
    }

    // A whole build for a record, kept as a change (the shop's buying, which saves the build first).
    public func KeepBuild(record: TweakDBID, text: String) {
        this.Keep(record, text);
    }

    // The co-op tick: an owner's car that's out here, and that this machine leads (not a partner's car it mirrors),
    // puts its saved build in when the session has none, so everyone sees it.
    public func SeedBuilds() {
        if !VCStateReady() {
            return;
        }
        for entity in this.m_seenEntities {
            let vehicle = GameInstance.FindEntityByID(this.GetGameInstance(), entity) as VehicleObject;
            if IsDefined(vehicle) {
                let record = vehicle.GetRecordID();
                if !ArrayContains(this.m_seeded, record) && !ArrayContains(this.m_sessionRecords, record) && VCLeads(vehicle) {
                    let text = this.GetBuildText(record);
                    if StrLen(text) > 0 && this.Owns(record) {
                        ArrayPush(this.m_seeded, record);
                        this.PutState(VCEngine.SessionKey(record), "s|" + text);
                        this.Note(s"our build of \(VCEngine.SessionKey(record)) goes into the session");
                    }
                }
            }
        }
    }

    // A world loaded in a session (Coop.reds): the session's builds as NightCoop holds them here, since its events
    // may have come before this world's systems started. A change to a car we own that our save doesn't have yet (one
    // made while we were loading) goes into it now.
    public func LoadSession() {
        let found = 0;
        let kept = 0;
        for record in this.m_records {
            let value = VCSessionValue(record);
            if StrLen(value) > 2 {
                let text = StrRight(value, StrLen(value) - 2);
                let before = this.WornText(record);
                this.SetSessionText(record, text);
                found += 1;
                if StrBeginsWith(value, "c|") && this.Owns(record) && !Equals(this.GetBuildText(record), text) {
                    this.SetBuildText(record, text);
                    kept += 1;
                }
                let vehicle = this.VehicleOf(record);
                if IsDefined(vehicle) && !Equals(before, this.WornText(record)) {
                    this.Rebuild(vehicle);
                }
            }
        }
        this.Note(s"the session's builds read: \(found), \(kept) of them changes to our cars kept now");
    }

    // A session started: our builds go in again when our cars are out (SeedBuilds).
    public func ForgetSeeds() {
        ArrayClear(this.m_seeded);
    }

    // A session ended: its builds are gone, and cars go back to our saved ones (NightCoop's removals do the same;
    // this doesn't wait for them).
    public func ForgetSession() {
        let records = this.m_sessionRecords;
        let texts = this.m_sessionTexts;
        ArrayClear(this.m_sessionRecords);
        ArrayClear(this.m_sessionTexts);
        ArrayClear(this.m_seeded);
        ArrayClear(this.m_outKeys);
        ArrayClear(this.m_outValues);
        ArrayClear(this.m_outFailed);
        ArrayClear(this.m_peerNumbers);
        ArrayClear(this.m_peerNames);
        ArrayClear(this.m_partnerLed);
        let i = 0;
        while i < ArraySize(records) {
            let vehicle = this.VehicleOf(records[i]);
            if IsDefined(vehicle) && !Equals(texts[i], this.GetBuildText(records[i])) {
                this.Rebuild(vehicle);
            }
            i += 1;
        }
    }

    public func SetBuildText(record: TweakDBID, text: String) {
        let i = ArraySize(this.m_buildRecords) - 1;
        while i >= 0 {
            if this.m_buildRecords[i] == record {
                ArrayErase(this.m_buildRecords, i);
                ArrayErase(this.m_buildTexts, i);
            }
            i -= 1;
        }
        let rest = text;
        while StrLen(rest) > 0 {
            let piece = StrLen(rest) > 200 ? StrLeft(rest, 200) : rest;
            ArrayPush(this.m_buildRecords, record);
            ArrayPush(this.m_buildTexts, StringToName(piece));
            rest = StrLen(rest) > 200 ? StrRight(rest, StrLen(rest) - 200) : "";
        }
    }

    public func GetNote() -> String {
        return this.m_note;
    }

    // --- building ---

    private cb func OnExtract(event: ref<EntityBuilderEvent>) {
        let builder = event.GetEntityBuilder();
        if !builder.HasAppearance() {
            return;
        }
        let look = builder.GetAppearanceName();
        let record = builder.GetRecordID();
        let entity = builder.GetEntityID();
        let how = "called";
        if !this.IsOurs(record) {
            let i = ArrayFindFirst(this.m_pendingLooks, look);
            if i < 0 {
                return;
            }
            record = this.m_pendingRecords[i];
            entity = this.m_pendingEntities[i];
            ArrayErase(this.m_pendingLooks, i);
            ArrayErase(this.m_pendingRecords, i);
            ArrayErase(this.m_pendingEntities, i);
            how = "rebuilt";
        } else if !ArrayContains(this.m_builtRecords, record) {
            ArrayPush(this.m_builtRecords, record);
        }
        let cat = this.CatalogOf(record);
        let text = this.WornText(record);
        // A car without a build is built as the game makes it: nothing to put on and nothing to note (V's own cars
        // are ours too since 2026-11-06, and most never get a build).
        if StrLen(text) == 0 {
            return;
        }
        let build = VCBuild.Parse(text);
        this.m_builds += 1;
        this.Note(s"build \(this.m_builds): \(TDBID.ToStringDEBUG(record)) \(how)" + (this.HasSessionBuild(record) ? " with the session's build" : "")
            + s" in \(NameToString(look)); " + this.Apply(builder.GetAppearance(), cat, NameToString(look), build));
    }

    // Puts a build's parts, paints and kits on a look being built, before the car exists.
    private func Apply(appearance: ref<EntityBuilderAppearanceWrapper>, cat: CName, look: String, build: ref<VCBuild>) -> String {
        let parts = appearance.GetComponents();
        let controller: ref<entVisualControllerComponent>;
        for part in parts {
            let found = part as entVisualControllerComponent;
            if IsDefined(found) {
                controller = found;
            }
        }
        let base = VCData.BaseLook(look);
        let style = VCData.StyleOf(cat, base);
        let swapped = 0;
        let painted = 0;
        let added = 0;
        let missing = 0;
        for slot in VCData.Names(cat, "slots") {
            let i = build.SlotIndex(slot);
            let option = i >= 0 ? build.options[i] : n"";
            let chosenPaint = i >= 0 ? build.paints[i] : n"";
            // A slot the build leaves alone matters only to a whole-car paint, on the part the style has there.
            let inEffect = IsNameValid(option) ? option : VCData.StyleOption(cat, style, slot);
            if IsNameValid(inEffect) && (IsNameValid(option) || IsNameValid(chosenPaint) || IsNameValid(build.paint)) {
                let key = "option." + NameToString(inEffect) + ".";
                let corners = VCData.Names(cat, "slot." + NameToString(slot) + ".corners");
                let meshes = VCData.Paths(cat, key + "meshes");
                let shadows = VCData.Paths(cat, key + "shadows");
                let offered = VCData.Names(cat, key + "paints");
                let c = 0;
                while c < ArraySize(corners) && c < ArraySize(meshes) {
                    let name = VCData.PartOf(cat, base, slot, corners[c]);
                    let mesh = this.FindMesh(parts, name);
                    if IsDefined(mesh) {
                        let had = mesh.meshAppearance;
                        if IsNameValid(option) {
                            mesh.mesh *= meshes[c];
                            if c < ArraySize(shadows) && ResRef.IsValid(shadows[c]) {
                                let shadow = this.FindShadow(parts, name);
                                if IsDefined(shadow) {
                                    shadow.mesh *= shadows[c];
                                    this.UpdateDependency(controller, shadow);
                                }
                            }
                            swapped += 1;
                        }
                        // The paint, top layer first: the part's own, the whole car's if the part offers it, the
                        // look's paint carried over to a swapped part that offers it, else the part's default.
                        let paint = had;
                        if IsNameValid(chosenPaint) {
                            paint = chosenPaint;
                        } else if IsNameValid(build.paint) && VCData.Has(offered, build.paint) {
                            paint = build.paint;
                        } else if IsNameValid(option) && !VCData.Has(offered, had) {
                            paint = VCData.Name(cat, key + "defaultPaint");
                        }
                        if !Equals(paint, had) {
                            painted += 1;
                        }
                        mesh.meshAppearance = paint;
                        this.UpdateDependency(controller, mesh);
                    } else if IsNameValid(option) {
                        // The look has no such part (the police body over the stock one, on a Suburban): it's added
                        // on the slot's mount point, where the looks that have it carry it.
                        let paint = IsNameValid(chosenPaint) ? chosenPaint
                            : IsNameValid(build.paint) && VCData.Has(offered, build.paint) ? build.paint
                            : VCData.Name(cat, key + "defaultPaint");
                        let shadow = c < ArraySize(shadows) ? shadows[c] : r"";
                        if this.AddSlotPart(appearance, cat, slot, c, corners[c], meshes[c], shadow, paint) {
                            added += 1;
                        } else {
                            missing += 1;
                        }
                    }
                    c += 1;
                }
            }
        }
        let wheels = this.ApplyWheels(parts, controller, cat, base, build);
        let kitParts = 0;
        let k = 0;
        while k < ArraySize(build.kits) {
            kitParts += this.AddKit(appearance, parts, cat, base, build, build.kits[k], build.kitOffsets[k]);
            k += 1;
        }
        return s"\(swapped) parts swapped, \(painted) repainted, \(added) added where the look has none, \(missing) failed, \(wheels) wheel parts fitted, \(kitParts) kit parts added";
    }

    // --- wheels from the shared list ---

    public static func Corners() -> array<CName> {
        return [n"fl", n"fr", n"bl", n"br", n"f", n"b"];
    }

    // The car's own wheel on an axle (catalog wheelFit, measured from its stock pair): x its tire's radius, y the
    // tire's width, z its rim's radius; zeros when the catalog has none.
    private func OwnWheel(cat: CName, front: Bool) -> Vector3 {
        let own = TweakDBInterface.GetVector3Array(VCData.Key(cat, "wheelFit"));
        let none: Vector3;
        if ArraySize(own) < 2 {
            return none;
        }
        return front ? own[0] : own[1];
    }

    // A set's measured pair: x its tire's radius, y the tire's width, z its rim's radius.
    private static func SetSize(set: CName) -> Vector3 {
        let none: Vector3;
        return IsNameValid(set) ? TweakDBInterface.GetVector3(VCData.WheelKey(set, "size"), none) : none;
    }

    private static func Scale(width: Float, size: Float) -> Vector3 {
        let scale: Vector3;
        scale.X = width;
        scale.Y = size;
        scale.Z = size;
        return scale;
    }

    // How big a corner's tire sits: always the car's own tire size on that axle, so the car sits as it should, times
    // the build's fit; a tire from the shared list is scaled to it. x across (width), y and z the size.
    private func TireScale(cat: CName, tire: CName, front: Bool, fit: Vector4) -> Vector3 {
        let mul = VCBuild.FitScale(fit);
        let width = mul.Y;
        let size = mul.X;
        let own = this.OwnWheel(cat, front);
        let theirs = VCEngine.SetSize(tire);
        if IsNameValid(tire) && own.X > 0.0 && theirs.X > 0.0 && theirs.Y > 0.0 {
            size *= own.X / theirs.X;
            width *= own.Y / theirs.Y;
        }
        return VCEngine.Scale(width, size);
    }

    // How big a corner's rim sits: sized to fill the tire it sits in (rims and tires are chosen apart, 2026-11-07).
    // The tire's inside is its set's rim radius, or the car's own rim's, at the tire's scale, so the wheel's size
    // (fit x) takes the rim with it: the game only stretches a part evenly, and a tire grown alone would leave a gap
    // around the rim. Its width is the car's own wheels' width times its own Width setting (fit z), whatever the
    // tire's: each has its own, to match one to the other (user, 2026-11-07: "changing the width of a tire changes
    // the width of the wheel as well", and a width for the rim too). A rim's own width is measured by the tire it
    // came with. Without the measurements the rim takes its Width setting and the tire's size.
    private func RimScale(cat: CName, rim: CName, tire: CName, front: Bool, fit: Vector4) -> Vector3 {
        let tireScale = this.TireScale(cat, tire, front, fit);
        let mul = VCBuild.FitScale(fit);
        let own = this.OwnWheel(cat, front);
        let tireSize = VCEngine.SetSize(tire);
        let rimSize = VCEngine.SetSize(rim);
        let inside = IsNameValid(tire) ? tireSize.Z * tireScale.Y : own.Z * mul.X;
        let rimRadius = IsNameValid(rim) ? rimSize.Z : own.Z;
        let rimWidth = IsNameValid(rim) ? rimSize.Y : own.Y;
        if inside <= 0.0 || rimRadius <= 0.0 || rimWidth <= 0.0 || own.Y <= 0.0 {
            return VCEngine.Scale(mul.Z, tireScale.Y);
        }
        return VCEngine.Scale(mul.Z * own.Y / rimWidth, inside / rimRadius);
    }

    // Where a part must be moved along the axle so its middle is where this car's own tire sits (catalog wheelCenter).
    // Pivots differ by up to 20 cm from car to car, and a part scaled about its pivot slides too, so without this a
    // wheel from elsewhere sat in or out of the arch and a rim sat off-centre in its tire (measured 2026-11-08,
    // experiments/tool/wheel-fit.py). scaleX is the part's width scale; set the rim's or tire's set, the middle being
    // that set's tire's (a rim keeps the place it had against the tire it came with).
    private func AxleShift(cat: CName, set: CName, front: Bool, scaleX: Float) -> Float {
        let none: Vector3;
        let own = TweakDBInterface.GetVector3(VCData.Key(cat, "wheelCenter"), none);
        let home = front ? own.X : own.Y;
        let middle = IsNameValid(set) ? TweakDBInterface.GetFloat(VCData.WheelKey(set, "tireCenter"), home) : home;
        return home - scaleX * middle;
    }

    // For Verify: a wheel part's place along its axle, the catalog's place for that slot and corner plus its shift.
    private static func PlaceProblem(cat: CName, slot: String, corner: CName, part: ref<MeshComponent>, shift: Float) -> String {
        let corners = VCData.Names(cat, "slot." + slot + ".corners");
        let positions = TweakDBInterface.GetVector3Array(VCData.Key(cat, "slot." + slot + ".positions"));
        let i = ArrayFindFirst(corners, corner);
        if i < 0 || i >= ArraySize(positions) {
            return "";
        }
        let at = part.GetLocalPosition();
        let want = positions[i].X + shift;
        if AbsF(at.X - want) > 0.005 {
            return s"\(NameToString(part.name)) sits \(FloatToStringPrec(at.X, 3)) along its axle, not \(FloatToStringPrec(want, 3)); ";
        }
        return "";
    }

    // The wheel groups a vehicle's axles sit in: the main ones, and a truck's or a six-wheeler's extra ones (the
    // Bratsk's second front axle is wheel_b on wheel_front_left_b). Every axle takes its side's set, fit and paint.
    public static func WheelGroups() -> array<String> {
        return ["wheel", "wheel_b", "wheel_c", "wheel_d", "wheel_e"];
    }

    // Puts the build's rims and tires on, axle by axle, onto the rim and tire parts the look has at each corner, with
    // their shadows, each scaled to fit (TireScale, RimScale), and paints the rims. Returns how many parts it changed.
    private func ApplyWheels(parts: array<ref<IComponent>>, controller: ref<entVisualControllerComponent>, cat: CName,
                             base: String, build: ref<VCBuild>) -> Int32 {
        let changed = 0;
        for group in VCEngine.WheelGroups() {
            for corner in VCEngine.Corners() {
                let front = StrBeginsWith(NameToString(corner), "f");
                let rimSet = front ? build.rimFront : build.rimBack;
                let tireSet = front ? build.tireFront : build.tireBack;
                let fit = front ? build.fitFront : build.fitBack;
                let paint = front ? build.wheelPaintFront : build.wheelPaintBack;
                if IsNameValid(rimSet) || IsNameValid(tireSet) || VCBuild.Fitted(fit) || IsNameValid(paint) {
                    let rim = this.FindMesh(parts, VCData.PartOf(cat, base, StringToName(group + ".wheel"), corner));
                    let tire = this.FindMesh(parts, VCData.PartOf(cat, base, StringToName(group + ".tire"), corner));
                    let rimScale = this.RimScale(cat, rimSet, tireSet, front, fit);
                    let tireScale = this.TireScale(cat, tireSet, front, fit);
                    changed += this.FitWheelPart(parts, controller, rim, rimSet, "rim", "rimShadow", paint, rimScale,
                        this.AxleShift(cat, rimSet, front, rimScale.X));
                    changed += this.FitWheelPart(parts, controller, tire, tireSet, "tire", "tireShadow", n"", tireScale,
                        this.AxleShift(cat, tireSet, front, tireScale.X));
                }
            }
        }
        return changed;
    }

    // paint: the rim's paint chosen in the build, or none for a set's own (a tire passes none and gets default).
    // shift: metres along the part's own axle (AxleShift); the part's shadow is bound to it and moves with it.
    private func FitWheelPart(parts: array<ref<IComponent>>, controller: ref<entVisualControllerComponent>,
                              part: ref<MeshComponent>, set: CName, meshPath: String, shadowPath: String, paint: CName,
                              scale: Vector3, shift: Float) -> Int32 {
        if !IsDefined(part) {
            return 0;
        }
        let rim = Equals(meshPath, "rim");
        let shadow = this.FindShadow(parts, part.name);
        if IsNameValid(set) {
            let mesh = TweakDBInterface.GetResRef(VCData.WheelKey(set, meshPath), r"");
            if !ResRef.IsValid(mesh) {
                return 0;
            }
            part.mesh *= mesh;
            part.meshAppearance = rim ? TweakDBInterface.GetCName(VCData.WheelKey(set, "defaultPaint"), n"default") : n"default";
            if IsDefined(shadow) {
                let shade = TweakDBInterface.GetResRef(VCData.WheelKey(set, shadowPath), r"");
                if ResRef.IsValid(shade) {
                    shadow.mesh *= shade;
                }
            }
        }
        if rim && IsNameValid(paint) {
            part.meshAppearance = paint;
        }
        part.visualScale = scale;
        // Every build starts from fresh parts, so this moves it once.
        let along = Quaternion.Transform(part.GetLocalOrientation(), new Vector4(shift, 0.0, 0.0, 0.0));
        part.SetLocalPosition(part.GetLocalPosition() + along);
        this.UpdateDependency(controller, part);
        if IsDefined(shadow) {
            shadow.visualScale = scale;
            this.UpdateDependency(controller, shadow);
        }
        return 1;
    }

    // A slot's part for a look that has none, on the slot's mount point at the place the looks that have it give
    // it (catalog: slot.<id>.mounts, .positions, .rotations), with its shadow.
    private func AddSlotPart(appearance: ref<EntityBuilderAppearanceWrapper>, cat: CName, slot: CName, c: Int32,
                             corner: CName, mesh: ResRef, shadow: ResRef, paint: CName) -> Bool {
        let key = "slot." + NameToString(slot) + ".";
        let mounts = VCData.Names(cat, key + "mounts");
        let positions = TweakDBInterface.GetVector3Array(VCData.Key(cat, key + "positions"));
        let rotations = TweakDBInterface.GetQuaternionArray(VCData.Key(cat, key + "rotations"));
        if c >= ArraySize(mounts) || c >= ArraySize(positions) || c >= ArraySize(rotations) || !ResRef.IsValid(mesh) {
            return false;
        }
        let part = new MeshComponent();
        part.name = VCEngine.SlotPartName(slot, corner);
        part.mesh *= mesh;
        part.meshAppearance = paint;
        let binding = new entHardTransformBinding();
        binding.bindName = n"vehicle_slots";
        binding.slotName = mounts[c];
        part.parentTransform = binding;
        let transform: WorldTransform;
        let p = positions[c];
        WorldTransform.SetPosition(transform, new Vector4(p.X, p.Y, p.Z, 1.0));
        WorldTransform.SetOrientation(transform, rotations[c]);
        part.localTransform = transform;
        appearance.AddComponent(part);
        if ResRef.IsValid(shadow) {
            let shade = new MeshComponent();
            shade.name = StringToName(NameToString(part.name) + "_shadow");
            shade.mesh *= shadow;
            let shadeBinding = new entHardTransformBinding();
            shadeBinding.bindName = part.name;
            shade.parentTransform = shadeBinding;
            appearance.AddComponent(shade);
        }
        return true;
    }

    public static func SlotPartName(slot: CName, corner: CName) -> CName {
        return StringToName("vc_slot_" + NameToString(slot) + "_" + NameToString(corner));
    }

    private func FindMesh(parts: array<ref<IComponent>>, name: CName) -> ref<MeshComponent> {
        if !IsNameValid(name) {
            return null;
        }
        for part in parts {
            if Equals(part.name, name) {
                return part as MeshComponent;
            }
        }
        return null;
    }

    // The shadow of a part: a mesh bound to it with "shadow" in its name, else one named after it with "_shadow"
    // (the Quadra's tire_01_fl_a_shadow hangs off the wheel's mount point, beside its tire).
    private func FindShadow(parts: array<ref<IComponent>>, parent: CName) -> ref<MeshComponent> {
        let named = StringToName(NameToString(parent) + "_shadow");
        for part in parts {
            let placed = part as IPlacedComponent;
            if IsDefined(placed) && StrContains(NameToString(part.name), "shadow") {
                let binding = placed.parentTransform as entHardTransformBinding;
                if IsDefined(binding) && Equals(binding.bindName, parent) {
                    return part as MeshComponent;
                }
            }
        }
        return this.FindMesh(parts, named);
    }

    // Points the visual controller's entry for a part at its new mesh and paint, since the game reloads parts
    // from that list when the car comes back into view.
    private func UpdateDependency(controller: ref<entVisualControllerComponent>, part: ref<MeshComponent>) {
        if !IsDefined(controller) {
            return;
        }
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
    }

    // --- placing kit parts ---
    // A kit part sits where its catalog puts it, moved and turned first by its own move, about its own place (the
    // user expects single parts moved more often than whole kits, 2026-11-06), then by the whole kit's, about the
    // middle of the kit's parts that hang off the same thing, so a light bar and its spotlight turn as one (eighth
    // suite run: turned each about its own spot, the spotlight drifted off). Turns are in degrees about the axes
    // of what the part hangs off: yaw about z (up), pitch about x, roll about y.

    public static func Turn(yaw: Float, pitch: Float, roll: Float) -> Quaternion {
        return VCEngine.AxisTurn(2, yaw) * VCEngine.AxisTurn(0, pitch) * VCEngine.AxisTurn(1, roll);
    }

    private static func AxisTurn(axis: Int32, degrees: Float) -> Quaternion {
        let half = Deg2Rad(degrees) * 0.5;
        let s = SinF(half);
        let q: Quaternion;
        q.i = axis == 0 ? s : 0.0;
        q.j = axis == 1 ? s : 0.0;
        q.k = axis == 2 ? s : 0.0;
        q.r = CosF(half);
        return q;
    }

    public static func Yaw(degrees: Float) -> Quaternion {
        return VCEngine.Turn(degrees, 0.0, 0.0);
    }

    // The middle of the kit's parts that hang off the same thing as part i.
    public static func KitPivot(positions: array<Vector3>, parents: array<CName>, i: Int32) -> Vector4 {
        let x = 0.0;
        let y = 0.0;
        let z = 0.0;
        let n = 0;
        let j = 0;
        while j < ArraySize(positions) {
            if j < ArraySize(parents) && i < ArraySize(parents) && Equals(parents[j], parents[i]) {
                x += positions[j].X;
                y += positions[j].Y;
                z += positions[j].Z;
                n += 1;
            }
            j += 1;
        }
        if n == 0 {
            return new Vector4(positions[i].X, positions[i].Y, positions[i].Z, 1.0);
        }
        let count = Cast<Float>(n);
        return new Vector4(x / count, y / count, z / count, 1.0);
    }

    // kitMove: x, y, z and w the yaw; kitTurn: x pitch, y roll; partMove likewise for the part alone.
    public static func KitPartPosition(positions: array<Vector3>, parents: array<CName>, i: Int32, kitMove: Vector4,
                                       kitTurn: Vector4, partMove: Vector4) -> Vector4 {
        let c = VCEngine.KitPivot(positions, parents, i);
        let p = positions[i];
        let from = new Vector4(p.X + partMove.X - c.X, p.Y + partMove.Y - c.Y, p.Z + partMove.Z - c.Z, 0.0);
        let turned = Quaternion.Transform(VCEngine.Turn(kitMove.W, kitTurn.X, kitTurn.Y), from);
        return new Vector4(c.X + turned.X + kitMove.X, c.Y + turned.Y + kitMove.Y, c.Z + turned.Z + kitMove.Z, 1.0);
    }

    public static func KitPartRotation(rotation: Quaternion, kitMove: Vector4, kitTurn: Vector4, partMove: Vector4,
                                       partTurn: Vector4) -> Quaternion {
        return VCEngine.Turn(kitMove.W, kitTurn.X, kitTurn.Y) * VCEngine.Turn(partMove.W, partTurn.X, partTurn.Y) * rotation;
    }

    // Adds a kit's parts, each with its shadow, on the part or mount point it hangs off, moved by the kit's offset.
    // Where a kit part hangs, by the catalog's parent (catalog/make-catalogs.py): a mount point
    // "vehicle_slots:<slot>", a slot's part "part:<slot>|<corner>" or its shadow "shadow:<slot>|<corner>", found
    // under whatever name this look gives it, a kit's part "kit:<kit>:<index>" if that kit is on, or a part's
    // own name. False when that isn't on the car.
    private func KitParent(parts: array<ref<IComponent>>, cat: CName, base: String, build: ref<VCBuild>,
                           parent: String, binding: ref<entHardTransformBinding>) -> Bool {
        if StrBeginsWith(parent, "vehicle_slots:") {
            binding.bindName = n"vehicle_slots";
            binding.slotName = StringToName(StrAfterFirst(parent, ":"));
            return true;
        }
        if StrBeginsWith(parent, "part:") || StrBeginsWith(parent, "shadow:") {
            let where = StrSplit(StrAfterFirst(parent, ":"), "|", true);
            if ArraySize(where) < 2 {
                return false;
            }
            let name = VCData.PartOf(cat, base, StringToName(where[0]), StringToName(where[1]));
            if !IsDefined(this.FindMesh(parts, name)) {
                return false;
            }
            if StrBeginsWith(parent, "shadow:") {
                let shadow = this.FindShadow(parts, name);
                if !IsDefined(shadow) {
                    return false;
                }
                name = shadow.name;
            }
            binding.bindName = name;
            return true;
        }
        if StrBeginsWith(parent, "kit:") {
            let what = StrSplit(parent, ":", true);
            if ArraySize(what) < 3 || build.KitIndex(StringToName(what[1])) < 0 {
                return false;
            }
            binding.bindName = StringToName("vc_kit_" + what[1] + "_" + what[2]);
            return true;
        }
        binding.bindName = StringToName(parent);
        return IsDefined(this.FindMesh(parts, binding.bindName));
    }

    private func AddKit(appearance: ref<EntityBuilderAppearanceWrapper>, parts: array<ref<IComponent>>, cat: CName,
                        base: String, build: ref<VCBuild>, kit: CName, offset: Vector4) -> Int32 {
        let key = "kit." + NameToString(kit) + ".";
        let names = VCData.Names(cat, key + "parts");
        let meshes = VCData.Paths(cat, key + "meshes");
        let shadows = VCData.Paths(cat, key + "shadows");
        let paints = VCData.Names(cat, key + "paints");
        let parents = VCData.Names(cat, key + "parents");
        let positions = TweakDBInterface.GetVector3Array(VCData.Key(cat, key + "positions"));
        let rotations = TweakDBInterface.GetQuaternionArray(VCData.Key(cat, key + "rotations"));
        let kitTurn = build.KitTurn(build.KitIndex(kit));
        let added = 0;
        let i = 0;
        while i < ArraySize(meshes) {
            let binding = new entHardTransformBinding();
            let present = this.KitParent(parts, cat, base, build, NameToString(parents[i]), binding);
            // A part that hangs off another is left out when that part isn't in this look.
            if present {
            let part = new MeshComponent();
            part.name = StringToName("vc_kit_" + NameToString(kit) + "_" + ToString(i));
            part.mesh *= meshes[i];
            part.meshAppearance = paints[i];
            part.parentTransform = binding;
            let transform: WorldTransform;
            let partMove = build.PartMove(kit, i);
            WorldTransform.SetPosition(transform, VCEngine.KitPartPosition(positions, parents, i, offset, kitTurn, partMove));
            WorldTransform.SetOrientation(transform, VCEngine.KitPartRotation(rotations[i], offset, kitTurn, partMove,
                build.PartTurn(kit, i)));
            part.localTransform = transform;
            appearance.AddComponent(part);
            if i < ArraySize(shadows) && ResRef.IsValid(shadows[i]) {
                let shadow = new MeshComponent();
                shadow.name = StringToName("vc_kit_" + NameToString(kit) + "_" + ToString(i) + "_shadow");
                shadow.mesh *= shadows[i];
                let shadowBinding = new entHardTransformBinding();
                shadowBinding.bindName = part.name;
                shadow.parentTransform = shadowBinding;
                appearance.AddComponent(shadow);
            }
            added += 1;
            }
            i += 1;
        }
        return added;
    }

    // --- rebuilding in place ---

    // Switches the car to its build's look, or to the other twin of the look it has, so the game builds it again
    // where it stands and the build goes on.
    // A car is rebuilt at most once in half a second: the dev panel once asked for a rebuild every frame, 30 a
    // second, and the car, with the user in it, was thrown into the air (2026-11-06). Asking again sooner waits
    // for the rest of the half second and then rebuilds once with the build as it is by then.
    public func Rebuild(vehicle: ref<VehicleObject>) {
        let record = vehicle.GetRecordID();
        if !this.IsOurs(record) {
            return;
        }
        let entity = vehicle.GetEntityID();
        let now = EngineTime.ToFloat(GameInstance.GetEngineTime(this.GetGameInstance()));
        let r = 0;
        let last = -1000.0;
        let at = -1;
        while r < ArraySize(this.m_rebuiltEntities) {
            if this.m_rebuiltEntities[r] == entity {
                at = r;
                last = this.m_rebuiltTimes[r];
            }
            r += 1;
        }
        if now - last < 0.5 {
            if !ArrayContains(this.m_waitingEntities, entity) {
                ArrayPush(this.m_waitingEntities, entity);
                let later = new VCRebuildLater();
                later.engine = this;
                later.entity = entity;
                GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(later, 0.5 - (now - last), false);
            }
            return;
        }
        if at >= 0 {
            this.m_rebuiltTimes[at] = now;
        } else {
            ArrayPush(this.m_rebuiltEntities, entity);
            ArrayPush(this.m_rebuiltTimes, now);
        }
        let build = VCBuild.Parse(this.BuildTextOf(vehicle));
        let current = NameToString(vehicle.GetCurrentAppearanceName());
        let base = IsNameValid(build.look) ? NameToString(build.look) : VCData.BaseLook(current);
        let target = Equals(current, base + "__vc_a") ? base + "__vc_b" : base + "__vc_a";
        let name = StringToName(target);
        // Two changes before the first rebuild lands ask for the same twin; one note of it is enough.
        let queued = false;
        let p = 0;
        while p < ArraySize(this.m_pendingLooks) {
            if Equals(this.m_pendingLooks[p], name) && this.m_pendingEntities[p] == entity {
                queued = true;
            }
            p += 1;
        }
        if !queued {
            ArrayPush(this.m_pendingLooks, name);
            ArrayPush(this.m_pendingRecords, record);
            ArrayPush(this.m_pendingEntities, entity);
        }
        vehicle.PrefetchAppearanceChange(name);
        vehicle.ScheduleAppearanceChange(name);
    }

    // A called car starts in its record's look; if its build has another, it switches to it as it appears. So
    // does one the game built without telling the builder its record (a spawn by another route), so the build
    // still goes on.
    public func OnVehicleAttached(vehicle: ref<VehicleObject>) {
        let record = vehicle.GetRecordID();
        if !this.IsOurs(record) {
            return;
        }
        let i = ArrayFindFirst(this.m_seenRecords, record);
        if i < 0 {
            ArrayPush(this.m_seenRecords, record);
            ArrayPush(this.m_seenEntities, vehicle.GetEntityID());
        } else {
            this.m_seenEntities[i] = vehicle.GetEntityID();
        }
        let built = ArrayContains(this.m_builtRecords, record);
        ArrayRemove(this.m_builtRecords, record);
        let text = this.BuildTextOf(vehicle);
        let build = VCBuild.Parse(text);
        let current = VCData.BaseLook(NameToString(vehicle.GetCurrentAppearanceName()));
        let otherLook = IsNameValid(build.look) && !Equals(current, NameToString(build.look));
        let unbuilt = !built && StrLen(text) > 0 && !Equals(text, "look=");
        if otherLook || unbuilt {
            this.Rebuild(vehicle);
        }
        // In a session its build reaches partners through the session's state: already there, or put in by the
        // co-op tick if it's ours (SeedBuilds).
        this.Note(s"attached: \(TDBID.ToStringDEBUG(record)) in \(NameToString(vehicle.GetCurrentAppearanceName()))"
            + (this.HasSessionBuild(record) ? " (the session's build)" : "")
            + (otherLook ? ", switching to its build's look" : unbuilt ? ", built without its build, rebuilding" : ""));
    }

    // The waiting rebuild of a car asked for too soon after its last one (Rebuild).
    public func RebuildLater(entity: EntityID) {
        ArrayRemove(this.m_waitingEntities, entity);
        let vehicle = GameInstance.FindEntityByID(this.GetGameInstance(), entity) as VehicleObject;
        if IsDefined(vehicle) {
            this.Rebuild(vehicle);
        }
    }

    public func NoteRefusedReset(vehicle: ref<VehicleObject>) {
        this.Note(s"kept \(TDBID.ToStringDEBUG(vehicle.GetRecordID()))'s look \(NameToString(vehicle.GetCurrentAppearanceName())) against the game's reset");
    }

    public func GetEntityOf(record: TweakDBID) -> EntityID {
        let i = ArrayFindFirst(this.m_seenRecords, record);
        let none: EntityID;
        return i >= 0 ? this.m_seenEntities[i] : none;
    }

    // --- choices, for the shop and the dev panel; each saves the build and rebuilds the car in place ---

    // What a car wears now. Every choice starts from it, so a change to a partner's car changes what's on it, not
    // our own saved build of that record.
    private func BuildFor(vehicle: ref<VehicleObject>) -> ref<VCBuild> {
        return VCBuild.Parse(this.BuildTextOf(vehicle));
    }

    // In co-op every player customizes every car (user, 2026-11-06); a change is kept by the car's owners whoever makes
    // it, through the session's build (Keep).
    private func Change(vehicle: ref<VehicleObject>, build: ref<VCBuild>) {
        this.Keep(vehicle.GetRecordID(), build.ToText());
        this.Rebuild(vehicle);
    }

    // A style or one of its factory paints: the look to build on. Part choices carry over.
    public func ChooseLook(vehicle: ref<VehicleObject>, look: CName) {
        let build = this.BuildFor(vehicle);
        build.look = look;
        this.Change(vehicle, build);
    }

    // A paint for the whole car, on every part that offers it; parts given their own paint keep it.
    public func ChooseCarPaint(vehicle: ref<VehicleObject>, paint: CName) {
        let build = this.BuildFor(vehicle);
        build.paint = paint;
        this.Change(vehicle, build);
    }

    // A set's rim and its own tire together on an axle: n"f", n"b", or anything else for both; none puts the car's
    // own back. (Tests and older calls; the screens choose rims and tires apart.)
    public func ChooseWheels(vehicle: ref<VehicleObject>, axle: CName, set: CName) {
        let build = this.BuildFor(vehicle);
        if !Equals(axle, n"b") {
            build.rimFront = set;
            build.tireFront = set;
        }
        if !Equals(axle, n"f") {
            build.rimBack = set;
            build.tireBack = set;
        }
        VCEngine.AutoFit(build, axle);
        this.Change(vehicle, build);
    }

    // A new rim or tire goes back to the automatic fit: both widths as measured, for the player to adjust from
    // (user, 2026-11-08). A fit can't be fully automatic: on the game's own pairs the best rule got size, width and
    // place all within 1 cm for 9% of them (experiments/tool/wheel-fit.py). The wheel's size stays: it's how big
    // the player wants the wheel, not a match between two parts.
    private static func AutoFit(build: ref<VCBuild>, axle: CName) {
        if !Equals(axle, n"b") {
            build.fitFront = new Vector4(build.fitFront.X, 0.0, 0.0, 0.0);
        }
        if !Equals(axle, n"f") {
            build.fitBack = new Vector4(build.fitBack.X, 0.0, 0.0, 0.0);
        }
    }

    // A rim from the shared list (a set's id) on an axle, or none for the car's own; the tire stays.
    public func ChooseRims(vehicle: ref<VehicleObject>, axle: CName, set: CName) {
        let build = this.BuildFor(vehicle);
        if !Equals(axle, n"b") {
            build.rimFront = set;
        }
        if !Equals(axle, n"f") {
            build.rimBack = set;
        }
        VCEngine.DropWheelSlots(build, "wheel");
        VCEngine.AutoFit(build, axle);
        this.Change(vehicle, build);
    }

    // A tire from the shared list (a set's id) on an axle, or none for the car's own; the rim stays and is sized to it.
    public func ChooseTires(vehicle: ref<VehicleObject>, axle: CName, set: CName) {
        let build = this.BuildFor(vehicle);
        if !Equals(axle, n"b") {
            build.tireFront = set;
        }
        if !Equals(axle, n"f") {
            build.tireBack = set;
        }
        VCEngine.DropWheelSlots(build, "tire");
        VCEngine.AutoFit(build, axle);
        this.Change(vehicle, build);
    }

    // Rims and tires are chosen only from the wheel lists now (2026-11-07), so a rim or tire slot's part an older
    // build chose in the Parts tab goes when a rim or tire is chosen: "Car's own" then means the style's own.
    private static func DropWheelSlots(build: ref<VCBuild>, kind: String) {
        for group in VCEngine.WheelGroups() {
            build.ClearSlot(StringToName(group + "." + kind));
        }
    }

    // Whether a slot is a rim or tire slot the wheel lists stand for (a wheel group's .wheel or .tire, on a car with
    // wheel sizes); those aren't listed with the other parts. A sub-slot (wheel.wheel.wheel_a1880) is a part of its own.
    public static func IsWheelSlot(cat: CName, slot: CName) -> Bool {
        let own = TweakDBInterface.GetVector3Array(VCData.Key(cat, "wheelFit"));
        if ArraySize(own) < 2 {
            return false;
        }
        let s = NameToString(slot);
        for group in VCEngine.WheelGroups() {
            if Equals(s, group + ".wheel") || Equals(s, group + ".tire") {
                return true;
            }
        }
        return false;
    }

    // The rims' paint on an axle (n"f", n"b", or both), on a set's rims or the car's own; none for the set's own.
    public func ChooseWheelPaint(vehicle: ref<VehicleObject>, axle: CName, paint: CName) {
        let build = this.BuildFor(vehicle);
        if !Equals(axle, n"b") {
            build.wheelPaintFront = paint;
        }
        if !Equals(axle, n"f") {
            build.wheelPaintBack = paint;
        }
        this.Change(vehicle, build);
    }

    // How big an axle's wheels sit, in percent of the car's own: the wheel's size and the tire's width. The rim's
    // own width stays.
    public func SetWheelFit(vehicle: ref<VehicleObject>, axle: CName, size: Float, width: Float) {
        let build = this.BuildFor(vehicle);
        if !Equals(axle, n"b") {
            build.fitFront = new Vector4(size, width, build.fitFront.Z, 0.0);
        }
        if !Equals(axle, n"f") {
            build.fitBack = new Vector4(size, width, build.fitBack.Z, 0.0);
        }
        this.Change(vehicle, build);
    }

    // The rims' width on an axle, in percent of the car's own wheels' width; the tire's stays (user, 2026-11-07).
    public func SetRimWidth(vehicle: ref<VehicleObject>, axle: CName, width: Float) {
        let build = this.BuildFor(vehicle);
        if !Equals(axle, n"b") {
            build.fitFront = new Vector4(build.fitFront.X, build.fitFront.Y, width, 0.0);
        }
        if !Equals(axle, n"f") {
            build.fitBack = new Vector4(build.fitBack.X, build.fitBack.Y, width, 0.0);
        }
        this.Change(vehicle, build);
    }

    public func ChooseOption(vehicle: ref<VehicleObject>, slot: CName, option: CName) {
        let build = this.BuildFor(vehicle);
        build.SetOption(slot, option, n"");
        this.Change(vehicle, build);
    }

    // A paint for a slot's part; without a part chosen, the part the look has.
    public func ChoosePaint(vehicle: ref<VehicleObject>, slot: CName, paint: CName) {
        let record = vehicle.GetRecordID();
        let cat = this.CatalogOf(record);
        let build = this.BuildFor(vehicle);
        let i = build.SlotIndex(slot);
        let option = i >= 0 ? build.options[i] : n"";
        if !IsNameValid(option) {
            let look = IsNameValid(build.look) ? NameToString(build.look) : NameToString(vehicle.GetCurrentAppearanceName());
            option = VCData.StyleOption(cat, VCData.StyleOf(cat, look), slot);
        }
        if !IsNameValid(option) {
            return;
        }
        build.SetOption(slot, option, paint);
        this.Change(vehicle, build);
    }

    public func ClearSlot(vehicle: ref<VehicleObject>, slot: CName) {
        let build = this.BuildFor(vehicle);
        build.ClearSlot(slot);
        this.Change(vehicle, build);
    }

    public func ToggleKit(vehicle: ref<VehicleObject>, kit: CName) -> Bool {
        let build = this.BuildFor(vehicle);
        let on = build.ToggleKit(kit);
        this.Change(vehicle, build);
        return on;
    }

    // Moves a kit by a step on the car at once (no rebuild needed) and saves it: the whole kit (part -1) or one of its
    // parts. move: x, y, z in metres and w the yaw; turn: x pitch, y roll; degrees.
    public func NudgeKit(vehicle: ref<VehicleObject>, kit: CName, part: Int32, move: Vector4, turn: Vector4) {
        let build = this.BuildFor(vehicle);
        if build.KitIndex(kit) < 0 {
            return;
        }
        build.Nudge(kit, part, move, turn);
        this.SaveAndPlaceKit(vehicle, build, kit);
    }

    // The whole kit by a step, without pitch or roll, as before.
    public func MoveKit(vehicle: ref<VehicleObject>, kit: CName, delta: Vector4) {
        this.NudgeKit(vehicle, kit, -1, delta, new Vector4(0.0, 0.0, 0.0, 0.0));
    }

    // Puts a kit (part -1) or one of its parts back where it came.
    public func ResetKitMoves(vehicle: ref<VehicleObject>, kit: CName, part: Int32) {
        let build = this.BuildFor(vehicle);
        build.ResetKitMoves(kit, part);
        this.SaveAndPlaceKit(vehicle, build, kit);
    }

    // Kept like any change (Change), but placed on the car here without a rebuild; partners' cars rebuild.
    private func SaveAndPlaceKit(vehicle: ref<VehicleObject>, build: ref<VCBuild>, kit: CName) {
        let record = vehicle.GetRecordID();
        let cat = this.CatalogOf(record);
        this.Keep(record, build.ToText());
        let k = build.KitIndex(kit);
        if k < 0 {
            return;
        }
        let offset = build.kitOffsets[k];
        let kitTurn = build.KitTurn(k);
        let positions = TweakDBInterface.GetVector3Array(VCData.Key(cat, "kit." + NameToString(kit) + ".positions"));
        let rotations = TweakDBInterface.GetQuaternionArray(VCData.Key(cat, "kit." + NameToString(kit) + ".rotations"));
        let parents = VCData.Names(cat, "kit." + NameToString(kit) + ".parents");
        let prefix = "vc_kit_" + NameToString(kit) + "_";
        for part in vehicle.GetComponents() {
            let name = NameToString(part.name);
            let placed = part as IPlacedComponent;
            if IsDefined(placed) && StrBeginsWith(name, prefix) && !StrEndsWith(name, "_shadow") {
                let i = StringToInt(StrRight(name, StrLen(name) - StrLen(prefix)));
                if i < ArraySize(positions) && i < ArraySize(rotations) {
                    let partMove = build.PartMove(kit, i);
                    placed.SetLocalPosition(VCEngine.KitPartPosition(positions, parents, i, offset, kitTurn, partMove));
                    placed.SetLocalOrientation(VCEngine.KitPartRotation(rotations[i], offset, kitTurn, partMove,
                        build.PartTurn(kit, i)));
                }
            }
        }
    }

    public func ResetBuild(vehicle: ref<VehicleObject>) {
        this.Change(vehicle, new VCBuild());
    }

    // A whole build at once, as text: the screen's undo and "back to how it was".
    public func ApplyBuildText(vehicle: ref<VehicleObject>, text: String) {
        this.Change(vehicle, VCBuild.Parse(text));
    }

    // The nearest of our cars seen in the world, within a radius of a point, or none.
    public func NearestOurs(at: Vector4, radius: Float) -> ref<VehicleObject> {
        let best: ref<VehicleObject>;
        let bestDistance = radius;
        for entity in this.m_seenEntities {
            let vehicle = GameInstance.FindEntityByID(this.GetGameInstance(), entity) as VehicleObject;
            if IsDefined(vehicle) {
                let d = Vector4.Distance(vehicle.GetWorldPosition(), at);
                if d <= bestDistance {
                    best = vehicle;
                    bestDistance = d;
                }
            }
        }
        return best;
    }

    // The car of a record if it's in the world now.
    public func VehicleOf(record: TweakDBID) -> ref<VehicleObject> {
        let entity = this.GetEntityOf(record);
        if !EntityID.IsDefined(entity) {
            return null;
        }
        let vehicle = GameInstance.FindEntityByID(this.GetGameInstance(), entity) as VehicleObject;
        return IsDefined(vehicle) && vehicle.GetRecordID() == record ? vehicle : null;
    }

    // The quick fix: the game's repair, then the dents and broken glass, where the car stands (job repair,
    // 2026-11-06: held; parts that came off stay off, and a rebuild would put the dents back).
    public func QuickFix(vehicle: ref<VehicleObject>) {
        vehicle.QueueEvent(new VehicleRepairEvent());
        vehicle.DestructionResetGrid();
        vehicle.DestructionResetGlass();
        this.Note(s"quick fix on \(TDBID.ToStringDEBUG(vehicle.GetRecordID()))");
    }

    // --- checks, for tests: whether every saved choice is on the car as the build says ---

    public func Verify(vehicle: ref<VehicleObject>) -> String {
        let record = vehicle.GetRecordID();
        let cat = this.CatalogOf(record);
        if !IsNameValid(cat) {
            return "not a customizable car";
        }
        let build = VCBuild.Parse(this.BuildTextOf(vehicle));
        let parts = vehicle.GetComponents();
        let look = VCData.BaseLook(NameToString(vehicle.GetCurrentAppearanceName()));
        let problems = "";
        let checked = 0;
        if IsNameValid(build.look) && !Equals(look, NameToString(build.look)) {
            problems += s"look is \(look), build wants \(NameToString(build.look)); ";
        }
        let style = VCData.StyleOf(cat, look);
        for slot in VCData.Names(cat, "slots") {
            let i = build.SlotIndex(slot);
            let option = i >= 0 ? build.options[i] : n"";
            let chosenPaint = i >= 0 ? build.paints[i] : n"";
            let inEffect = IsNameValid(option) ? option : VCData.StyleOption(cat, style, slot);
            if IsNameValid(inEffect) && (IsNameValid(option) || IsNameValid(chosenPaint) || IsNameValid(build.paint)) {
                let key = "option." + NameToString(inEffect) + ".";
                let corners = VCData.Names(cat, "slot." + NameToString(slot) + ".corners");
                let meshes = VCData.Paths(cat, key + "meshes");
                let offered = VCData.Names(cat, key + "paints");
                let wantPaint = IsNameValid(chosenPaint) ? chosenPaint
                    : IsNameValid(build.paint) && VCData.Has(offered, build.paint) ? build.paint : n"";
                let c = 0;
                while c < ArraySize(corners) && c < ArraySize(meshes) {
                    let name = VCData.PartOf(cat, look, slot, corners[c]);
                    if !IsNameValid(name) && IsNameValid(option) {
                        name = VCEngine.SlotPartName(slot, corners[c]); // added, since the look has none
                    }
                    let mesh = this.FindMesh(parts, name);
                    if !IsNameValid(name) {
                        // the look has no such part and none was chosen: nothing to check
                    } else if !IsDefined(mesh) {
                        problems += s"\(NameToString(name)) missing; ";
                    } else {
                        let ref = mesh.mesh;
                        if IsNameValid(option) && ResourceAsyncRef.GetHash(ref) != ResRef.GetHash(meshes[c]) {
                            problems += s"\(NameToString(name)) has another mesh; ";
                        }
                        if IsNameValid(wantPaint) && !Equals(mesh.meshAppearance, wantPaint) {
                            problems += s"\(NameToString(name)) is painted \(NameToString(mesh.meshAppearance)), not \(NameToString(wantPaint)); ";
                        }
                        checked += 1;
                    }
                    c += 1;
                }
            }
        }
        // Wheels: each axle's rims and tires carry the set's meshes and the chosen paint, at the size they should sit.
        for group in VCEngine.WheelGroups() {
        for corner in VCEngine.Corners() {
            let front = StrBeginsWith(NameToString(corner), "f");
            let rimSet = front ? build.rimFront : build.rimBack;
            let tireSet = front ? build.tireFront : build.tireBack;
            let fit = front ? build.fitFront : build.fitBack;
            let paint = front ? build.wheelPaintFront : build.wheelPaintBack;
            if IsNameValid(rimSet) || IsNameValid(tireSet) || VCBuild.Fitted(fit) || IsNameValid(paint) {
                let want = this.TireScale(cat, tireSet, front, fit);
                let wantRim = this.RimScale(cat, rimSet, tireSet, front, fit);
                let rim = this.FindMesh(parts, VCData.PartOf(cat, look, StringToName(group + ".wheel"), corner));
                let tire = this.FindMesh(parts, VCData.PartOf(cat, look, StringToName(group + ".tire"), corner));
                if IsDefined(rim) && IsDefined(tire) {
                    if IsNameValid(paint) && !Equals(rim.meshAppearance, paint) {
                        problems += s"\(NameToString(rim.name)) is painted \(NameToString(rim.meshAppearance)), not \(NameToString(paint)); ";
                    }
                    if IsNameValid(rimSet) {
                        let ref = rim.mesh;
                        if ResourceAsyncRef.GetHash(ref) != ResRef.GetHash(TweakDBInterface.GetResRef(VCData.WheelKey(rimSet, "rim"), r"")) {
                            problems += s"\(NameToString(rim.name)) isn't the chosen rim; ";
                        }
                    }
                    if IsNameValid(tireSet) {
                        let tref = tire.mesh;
                        if ResourceAsyncRef.GetHash(tref) != ResRef.GetHash(TweakDBInterface.GetResRef(VCData.WheelKey(tireSet, "tire"), r"")) {
                            problems += s"\(NameToString(tire.name)) isn't the chosen tire; ";
                        }
                    }
                    let got = tire.visualScale;
                    if AbsF(got.X - want.X) > 0.01 || AbsF(got.Y - want.Y) > 0.01 {
                        problems += s"\(NameToString(tire.name)) sits at \(FloatToStringPrec(got.Y, 2)) x \(FloatToStringPrec(got.X, 2)), not \(FloatToStringPrec(want.Y, 2)) x \(FloatToStringPrec(want.X, 2)); ";
                    }
                    let gotRim = rim.visualScale;
                    if AbsF(gotRim.X - wantRim.X) > 0.01 || AbsF(gotRim.Y - wantRim.Y) > 0.01 {
                        problems += s"\(NameToString(rim.name)) sits at \(FloatToStringPrec(gotRim.Y, 2)) x \(FloatToStringPrec(gotRim.X, 2)), not \(FloatToStringPrec(wantRim.Y, 2)) x \(FloatToStringPrec(wantRim.X, 2)); ";
                    }
                    problems += VCEngine.PlaceProblem(cat, group + ".tire", corner, tire, this.AxleShift(cat, tireSet, front, want.X));
                    problems += VCEngine.PlaceProblem(cat, group + ".wheel", corner, rim, this.AxleShift(cat, rimSet, front, wantRim.X));
                    checked += 2;
                }
            }
        }
        }
        let k = 0;
        while k < ArraySize(build.kits) {
            let kit = build.kits[k];
            let offset = build.kitOffsets[k];
            let positions = TweakDBInterface.GetVector3Array(VCData.Key(cat, "kit." + NameToString(kit) + ".positions"));
            let parents = VCData.Names(cat, "kit." + NameToString(kit) + ".parents");
            let prefix = "vc_kit_" + NameToString(kit) + "_";
            let found = 0;
            for part in parts {
                let name = NameToString(part.name);
                let placed = part as IPlacedComponent;
                if StrBeginsWith(name, prefix) {
                    found += 1;
                    let n = StringToInt(StrRight(name, StrLen(name) - StrLen(prefix)));
                    if IsDefined(placed) && !StrEndsWith(name, "_shadow") && n < ArraySize(positions) {
                        let want = VCEngine.KitPartPosition(positions, parents, n, offset, build.KitTurn(k),
                            build.PartMove(kit, n));
                        let at = placed.GetLocalPosition();
                        let dx = at.X - want.X;
                        let dy = at.Y - want.Y;
                        let dz = at.Z - want.Z;
                        if dx * dx + dy * dy + dz * dz > 0.0001 {
                            problems += s"\(name) sits \(FloatToStringPrec(SqrtF(dx * dx + dy * dy + dz * dz), 3)) m from its place; ";
                        }
                    }
                }
            }
            if found == 0 {
                problems += s"kit \(NameToString(kit)) not on the car; ";
            }
            checked += found;
            k += 1;
        }
        return StrLen(problems) == 0 ? s"ok (\(checked) parts checked)" : problems;
    }

    // What the engine reads from the catalog for a car's look, for tests: its style, the body that style has, and
    // whether that body offers primer red.
    public func Diagnose(vehicle: ref<VehicleObject>) -> String {
        let cat = this.CatalogOf(vehicle.GetRecordID());
        let look = VCData.BaseLook(NameToString(vehicle.GetCurrentAppearanceName()));
        let style = VCData.StyleOf(cat, look);
        let body = VCData.StyleOption(cat, style, n"base.body");
        let paints = VCData.Names(cat, "option." + NameToString(body) + ".paints");
        return s"catalog \(NameToString(cat)), look \(look), style \(NameToString(style)), body option \(NameToString(body)) with \(ArraySize(paints)) paints, primer_red "
            + (VCData.Has(paints, n"primer_red") ? "offered" : "not offered");
    }

    // --- garage ---

    public func Unlock(record: TweakDBID) -> Bool {
        return GameInstance.GetVehicleSystem(this.GetGameInstance()).EnablePlayerVehicleID(record, true, false);
    }

    public func IsUnlocked(record: TweakDBID) -> Bool {
        return GameInstance.GetVehicleSystem(this.GetGameInstance()).IsVehiclePlayerUnlocked(record);
    }

    // Takes a copy out of V's garage again (for the shop's sales gone back on, and tests cleaning up).
    public func Lock(record: TweakDBID) -> Bool {
        return GameInstance.GetVehicleSystem(this.GetGameInstance()).EnablePlayerVehicleID(record, false, false);
    }

    public func Call(record: TweakDBID) -> Bool {
        let vehicleRecord = TweakDBInterface.GetVehicleRecord(record);
        let kind = IsDefined(vehicleRecord) && IsDefined(vehicleRecord.Type()) ? vehicleRecord.Type().Type() : gamedataVehicleType.Car;
        return GameInstance.GetVehicleSystem(this.GetGameInstance()).SpawnPlayerVehicle(kind, record, false);
    }

    public func SendAway(record: TweakDBID) {
        let garageID: GarageVehicleID;
        garageID.recordID = record;
        GameInstance.GetVehicleSystem(this.GetGameInstance()).DespawnPlayerVehicle(garageID);
    }
}

public class VCRebuildLater extends DelayCallback {
    public let engine: wref<VCEngine>;
    public let entity: EntityID;

    public func Call() {
        if IsDefined(this.engine) {
            this.engine.RebuildLater(this.entity);
        }
    }
}

@wrapMethod(VehicleObject)
protected cb func OnGameAttached() -> Bool {
    let result = wrappedMethod();
    let engine = VCEngine.Get(this.GetGame());
    if IsDefined(engine) {
        engine.OnVehicleAttached(this);
    }
    return result;
}

// The game puts a CrystalCoat-capable car back on its record's look when the player gets in, and CrystalCoat
// Continuity does it as a car appears near the player; our cars keep the look their build gives them.
@wrapMethod(VehicleComponent)
public final func EnableCustomizableAppearance(val: Bool) -> Void {
    let vehicle = this.GetVehicle();
    let engine = IsDefined(vehicle) ? VCEngine.Get(vehicle.GetGame()) : null;
    // Only a car with a build: V's own cars keep CrystalCoat until they're customized.
    if IsDefined(engine) && engine.IsOurs(vehicle.GetRecordID()) && StrLen(engine.BuildTextOf(vehicle)) > 0 {
        engine.NoteRefusedReset(vehicle);
        return;
    }
    wrappedMethod(val);
}
