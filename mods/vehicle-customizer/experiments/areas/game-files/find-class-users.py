"""Find every file whose name table mentions a class (by default the Yaiba showroom's controller), with what it imports.
usage: python -I find-class-users.py [ClassName ...]"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "..", "tools"))
import rdar

WANTED = [w.encode() for w in (sys.argv[1:] or ["ComputerYaibaShowroomController", "RoboticArms"])]
ROOT = os.path.join(rdar.GAME, "archive", "pc")
for sub in ("content", "ep1"):
    for name in sorted(os.listdir(os.path.join(ROOT, sub))):
        if not name.endswith(".archive") or "audio" in name or "lang_" in name or "video" in name:
            continue
        a = rdar.Archive(os.path.join(ROOT, sub, name))
        for e in a.entries:
            try:
                head = a.read_segment(e[2])
            except Exception:
                continue
            if head[:4] != b"CR2W":
                continue
            hits = [w for w in WANTED if w in head]
            if not hits:
                continue
            try:
                c = rdar.CR2W(head)
                imports = [p for p, _cls, _f in c.imports][:12]
                classes = sorted(set(c.exports))[:6]
            except Exception:
                imports, classes = [], []
            print(f"{name} #{e[0]:016x} mentions {[h.decode() for h in hits]} classes {classes}")
            for p in imports:
                print(f"     imports {p}")
