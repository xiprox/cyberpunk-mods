"""Walk the game's archives. Every CR2W names the paths it imports, so reading them all
recovers real file names for anything vehicle-shaped. Writes a JSON catalogue."""
import collections
import json
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "..", "tools"))
import rdar

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "catalogue.json")
ROOT = os.path.join(rdar.GAME, "archive", "pc")
names = [("content", "basegame_4_appearance.archive"),
         ("content", "basegame_4_gamedata.archive"),
         ("content", "basegame_1_engine.archive"),
         ("content", "basegame_3_nightcity.archive"),
         ("ep1", "ep1_1_nightcity.archive"),
         ("ep1", "ep1_2_gamedata.archive")]

paths = set()
classes = collections.Counter()
per_archive = {}
t0 = time.time()
for sub, n in names:
    a = rdar.Archive(os.path.join(ROOT, sub, n))
    errs = 0
    cr2w = 0
    for i, e in enumerate(a.entries):
        if i % 50000 == 0:
            print(f"{n}: {i}/{len(a.entries)} paths={len(paths)} t={time.time()-t0:.0f}s", flush=True)
        try:
            head = a.read_segment(e[2])
            if head[:4] != b"CR2W":
                continue
            c = rdar.CR2W(head)
            cr2w += 1
            for p, _cls, _flags in c.imports:
                if "vehicle" in p.lower():
                    paths.add(p.lower())
            for s in c.strings.split(b"\0"):
                if b"\\" in s and b"vehicle" in s.lower():
                    try:
                        paths.add(s.decode("utf-8").lower())
                    except UnicodeDecodeError:
                        pass
        except Exception:
            errs += 1
    per_archive[n] = {"entries": len(a.entries), "cr2w": cr2w, "errors": errs}
    print(n, per_archive[n], flush=True)

# Which of the recovered names actually exist, and where?
where = {}
for sub, n in names:
    a = rdar.Archive(os.path.join(ROOT, sub, n))
    for p in paths:
        if rdar.fnv1a64(p) in a.files:
            where.setdefault(p, []).append(n)

json.dump({"per_archive": per_archive, "paths": sorted(paths), "where": where},
          open(OUT, "w", encoding="utf-8"), indent=0)
print("paths", len(paths), "present", len(where), f"t={time.time()-t0:.0f}s")
