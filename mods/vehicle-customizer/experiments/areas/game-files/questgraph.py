"""A quest phase's graph as text: each node with what it checks or does (facts, street cred tiers, trigger
areas, journal entries, phases), and where it leads. For finding what starts a gig.

  python -I questgraph.py <archive-hash-or-path> [filter-regex]

With a filter, prints only nodes whose description matches, plus the nodes that lead into them and out of them."""
import collections
import os
import re
import sys
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "..", "tools"))
import pkg
import rdar

TWEAK_NAMES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "tweakdb-names.txt")
_tdb = None


def tdb_name(tid):
    global _tdb
    if _tdb is None:
        _tdb = {}
        wanted = set()
    ln, crc = tid >> 32, tid & 0xFFFFFFFF
    if tid in _tdb:
        return _tdb[tid]
    with open(TWEAK_NAMES, encoding="utf-8", errors="replace") as f:
        for line in f:
            name = line.rstrip("\n").split("\t")[-1]
            if len(name) == ln and zlib.crc32(name.encode()) == crc:
                _tdb[tid] = name
                return name
    _tdb[tid] = hex(tid)
    return _tdb[tid]


def load(arg):
    depot = pkg.Depot()
    if re.fullmatch(r"(0x)?[0-9a-fA-F]{8,16}", arg):
        h = int(arg, 16)
        for a in reversed(depot.archives):
            if h in a.files:
                e = a.files[h]
                return pkg.Cooked(a.read_segment(e[2]), [a.read_segment(i) for i in range(e[2] + 1, e[3])], depot)
        raise SystemExit("not found")
    head, bufs = depot.load(arg)
    return pkg.Cooked(head, bufs, depot)


def main():
    c = load(sys.argv[1])
    flt = re.compile(sys.argv[2], re.I) if len(sys.argv) > 2 else None
    ex = c.exports

    def get(h):
        return ex[h[1] - 1] if isinstance(h, tuple) and h[0] == "export" and 0 < h[1] <= len(ex) else (None, None)

    def describe(cls, obj, depth=0):
        """What a node or condition checks or does, in a line."""
        if obj is None or depth > 4:
            return ""
        bits = []
        for k, v in obj.items():
            if k in ("sockets", "id", "connections"):
                continue
            if isinstance(v, tuple) and v[0] == "export":
                sub_cls, sub = get(v)
                d = describe(sub_cls, sub, depth + 1)
                if d:
                    bits.append(f"{k}=<{sub_cls.replace('quest', '')}: {d}>")
            elif isinstance(v, list):
                parts = []
                for x in v:
                    if isinstance(x, tuple) and x[0] == "export":
                        sc, so = get(x)
                        d = describe(sc, so, depth + 1)
                        if d:
                            parts.append(f"<{sc.replace('quest', '')}: {d}>")
                    elif x not in (None, ""):
                        parts.append(str(x))
                if parts:
                    bits.append(f"{k}=[{', '.join(parts)}]")
            elif k == "tierID" and isinstance(v, int):
                bits.append(f"tier={tdb_name(v)}")
            elif isinstance(v, (int, float)) and v == 0:
                continue
            elif v not in (None, "", "None") and not str(v).startswith("<"):
                bits.append(f"{k}={v}")
        return " ".join(bits)

    # nodes: exports with sockets; edges via socket connections
    socket_owner = {}
    nodes = {}
    for i, (cls, obj) in enumerate(ex, start=1):
        if isinstance(obj, dict) and isinstance(obj.get("sockets"), list) and cls.endswith("Definition") and cls != "questSocketDefinition":
            nodes[i] = (cls, obj)
            for s in obj["sockets"]:
                if isinstance(s, tuple):
                    socket_owner[s[1]] = i
    edges = collections.defaultdict(set)
    back = collections.defaultdict(set)
    for i, (cls, obj) in enumerate(ex, start=1):
        if cls == "graphGraphConnectionDefinition":
            src, dst = obj.get("source"), obj.get("destination")
            if isinstance(src, tuple) and isinstance(dst, tuple):
                a, b = socket_owner.get(src[1]), socket_owner.get(dst[1])
                if a and b:
                    edges[a].add(b)
                    back[b].add(a)
    text = {i: f"{cls.replace('quest', '').replace('NodeDefinition', '')}#{obj.get('id')} {describe(cls, obj)}" for i, (cls, obj) in nodes.items()}
    show = set(nodes) if not flt else {i for i, t in text.items() if flt.search(t)}
    if flt:
        for i in list(show):
            show |= back[i] | edges[i]
            for j in back[i]:
                show |= back[j]
    for i in sorted(show):
        print(f"[{i}] {text[i] if (flt and flt.search(text[i]) and len(sys.argv) > 3) else text[i][:400]}")
        if edges[i]:
            print(f"      -> {sorted(edges[i])}")


main()

