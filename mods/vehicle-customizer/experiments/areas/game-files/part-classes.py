"""Which component class each kind of car part uses, across every vehicle appearance."""
import collections
import json
import os

S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
apps = json.load(open(os.path.join(S, "apps.json"), encoding="utf-8"))

classes = collections.Counter()
by_part = collections.defaultdict(collections.Counter)
watched = ("bumper_f_01", "hood_a", "body_01", "wheel_01_fl_a", "tire_01_fl_a", "door_fl_a", "bumper_f_shadow")
for app in apps.values():
    for comp in app.values():
        for slot, c in comp.items():
            classes[c["cls"]] += 1
            if slot in watched:
                by_part[slot][c["cls"]] += 1
print("component classes:", classes.most_common())
for part, counts in by_part.items():
    print(f"  {part:18s} {counts.most_common(3)}")
