"""Reads CR2W objects and the RED packages cooked into their buffers (.app compiledData, .ent compiledData)."""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdar

ROOT = os.path.join(rdar.GAME, "archive", "pc")
ARCHIVES = [("content", "basegame_4_appearance.archive"), ("content", "basegame_4_gamedata.archive"),
            ("content", "basegame_1_engine.archive"), ("content", "basegame_3_nightcity.archive"),
            ("ep1", "ep1_1_nightcity.archive"), ("ep1", "ep1_2_gamedata.archive")]


class Depot:
    def __init__(self):
        self.archives = [rdar.Archive(os.path.join(ROOT, s, n)) for s, n in ARCHIVES]
        self.names = {}

    def add_names(self, paths):
        for p in paths:
            self.names[rdar.fnv1a64(p)] = p

    def find(self, path_or_hash):
        h = path_or_hash if isinstance(path_or_hash, int) else rdar.fnv1a64(path_or_hash)
        for a in reversed(self.archives):  # ep1 wins
            if h in a.files:
                return a, h
        return None, h

    def load(self, path_or_hash):
        a, h = self.find(path_or_hash)
        if a is None:
            return None
        e = a.files[h]
        head = a.read_segment(e[2])
        buffers = [a.read_segment(i) for i in range(e[2] + 1, e[3])]
        return head, buffers

    def name(self, h):
        return self.names.get(h, f"#{h:016x}")


FIXED = {"Bool": ("<B", 1), "Int8": ("<b", 1), "Uint8": ("<B", 1), "Int16": ("<h", 2), "Uint16": ("<H", 2),
         "Int32": ("<i", 4), "Uint32": ("<I", 4), "Int64": ("<q", 8), "Uint64": ("<Q", 8), "Float": ("<f", 4),
         "Double": ("<d", 8), "TweakDBID": ("<Q", 8), "CRUID": ("<Q", 8)}


class Package:
    """RED package: header, ref pool, name pool, chunks of (numFields, fields) objects."""

    def __init__(self, data, depot=None):
        self.d = data
        self.depot = depot
        version, flags, sections = struct.unpack_from("<BBH", data, 0)
        if sections == 7:
            n_cruid, refd, refs, named, names, chunkd, chunks = struct.unpack_from("<7I", data, 4)
            p = 0x20 + 4 + 8 * n_cruid  # ffff, count, then the CRUIDs
        else:
            refd, refs, named, names, chunkd, chunks = struct.unpack_from("<6I", data, 4)
            p = 0x1C
        self.base = p  # every offset below is relative to the end of that table
        b = self.base
        self.refs = []
        for o in range(refd, refs, 4):
            v = struct.unpack_from("<I", data, b + o)[0]
            off = v & 0x7FFFFF
            self.refs.append(struct.unpack_from("<Q", data, b + off)[0] if b + off + 8 <= len(data) else 0)
        self.names = []
        for o in range(named, names, 4):
            v = struct.unpack_from("<I", data, b + o)[0]
            off, size = v & 0xFFFFFF, v >> 24
            self.names.append(data[b + off:b + off + size].split(b"\0")[0].decode("utf-8", "replace"))
        self.chunks = []
        for o in range(chunkd, chunks, 8):
            t, off = struct.unpack_from("<II", data, b + o)
            self.chunks.append((self.names[t] if t < len(self.names) else f"?{t}", off))
        self.end = len(data) - b

    def nm(self, i):
        return self.names[i] if i < len(self.names) else f"?{i}"

    def read_obj(self, off, end):
        b = self.base
        d = self.d
        n = struct.unpack_from("<H", d, b + off)[0]
        fields = []
        p = b + off + 2
        for _ in range(n):
            ni, ti, fo = struct.unpack_from("<HHI", d, p)
            p += 8
            fields.append((self.nm(ni), self.nm(ti), fo))
        out = {}
        for i, (name, typ, fo) in enumerate(fields):
            fe = fields[i + 1][2] if i + 1 < len(fields) else end - off
            out[name] = self.value(typ, off + fo, off + fe)
        return out

    def value(self, typ, off, end):
        b = self.base
        d = self.d
        try:
            if typ in FIXED:
                return struct.unpack_from(FIXED[typ][0], d, b + off)[0]
            if typ == "CName":
                return self.nm(struct.unpack_from("<H", d, b + off)[0])
            if typ.startswith(("rRef:", "raRef:")):
                i = struct.unpack_from("<H", d, b + off)[0]
                h = self.refs[i] if i < len(self.refs) else 0
                return ("ref", self.depot.name(h) if self.depot else h)
            if typ.startswith(("handle:", "whandle:")):
                return ("chunk", struct.unpack_from("<i", d, b + off)[0])
            if typ == "String":
                return d[b + off + 1:b + end].decode("utf-8", "replace")
            if typ.startswith("array:"):
                inner = typ[6:]
                n = struct.unpack_from("<I", d, b + off)[0]
                p = off + 4
                if inner in FIXED:
                    size = FIXED[inner][1]
                    return [self.value(inner, p + i * size, p + (i + 1) * size) for i in range(n)]
                if inner == "CName" or inner.startswith(("rRef:", "raRef:")):
                    return [self.value(inner, p + i * 2, p + (i + 1) * 2) for i in range(n)]
                if inner.startswith(("handle:", "whandle:")):
                    return [self.value(inner, p + i * 4, p + (i + 1) * 4) for i in range(n)]
                out = []
                for _ in range(n):  # class elements: walk them to find their sizes
                    obj, size = self.read_sized(p, end)
                    out.append(obj)
                    p += size
                return out
            if end - off == 2:
                return self.nm(struct.unpack_from("<H", d, b + off)[0])  # an enum
            if end - off >= 2:
                return self.read_obj(off, end)
        except Exception as ex:  # keep walking; the fields that matter are simple ones
            return f"<{typ}: {ex}>"
        return f"<{typ}>"

    def read_sized(self, off, end):
        b = self.base
        n = struct.unpack_from("<H", self.d, b + off)[0]
        if n == 0:
            return {}, 2
        fields = [struct.unpack_from("<HHI", self.d, b + off + 2 + i * 8) for i in range(n)]
        # the last field's size is unknown without types; treat small simple ones exactly
        last_n, last_t, last_o = fields[-1]
        t = self.nm(last_t)
        if t in FIXED:
            total = last_o + FIXED[t][1]
        elif t == "CName" or t.startswith(("rRef:", "raRef:")):
            total = last_o + 2
        elif t.startswith(("handle:", "whandle:")):
            total = last_o + 4
        else:
            total = end - off
        return self.read_obj(off, off + total), total

    def objects(self, only=None):
        """Every chunk as (class, fields). With `only`, reads just those simple fields, which is fast and safe."""
        out = []
        for i, (cls, off) in enumerate(self.chunks):
            end = self.chunks[i + 1][1] if i + 1 < len(self.chunks) else self.end
            if only is None:
                out.append((cls, self.read_obj(off, end)))
                continue
            fields = {}
            n = struct.unpack_from("<H", self.d, self.base + off)[0]
            for j in range(n):
                ni, ti, fo = struct.unpack_from("<HHI", self.d, self.base + off + 2 + j * 8)
                name = self.nm(ni)
                if name in only:
                    typ = self.nm(ti)
                    if typ == "CName" or typ.startswith(("rRef:", "raRef:", "handle:", "whandle:")) or typ in FIXED:
                        fields[name] = self.value(typ, off + fo, off + fo + 8)
            out.append((cls, fields))
        return out


class Cooked:
    """A CR2W file: exports as dicts of simple properties, plus its buffers."""

    def __init__(self, head, buffers, depot=None):
        self.c = rdar.CR2W(head)
        self.head = head
        self.buffers = buffers
        self.depot = depot
        off, n, _ = self.c.tables[4]
        self.exports = []
        for i in range(n):
            cls, flags, parent, size, data_off, tmpl, crc = struct.unpack_from("<HHIIIII", head, off + i * 24)
            self.exports.append((self.c.names[cls], self.read_cr2w_obj(data_off, data_off + size)))

    def read_cr2w_obj(self, off, end):
        d = self.head
        p = off + 1  # leading zero
        out = {}
        while p + 2 <= end:
            ni = struct.unpack_from("<H", d, p)[0]
            if ni == 0:
                break
            ti, size = struct.unpack_from("<HI", d, p + 2)
            name, typ = self.c.names[ni], self.c.names[ti]
            out[name] = self.val(typ, p + 8, p + 4 + size)
            p += 4 + size
        return out

    def val(self, typ, off, end):
        d = self.head
        try:
            if typ in FIXED:
                return struct.unpack_from(FIXED[typ][0], d, off)[0]
            if typ == "CName":
                return self.c.names[struct.unpack_from("<H", d, off)[0]]
            if typ.startswith(("rRef:", "raRef:")):
                i = struct.unpack_from("<H", d, off)[0]
                return ("ref", self.c.imports[i - 1][0] if 0 < i <= len(self.c.imports) else None)
            if typ.startswith(("handle:", "whandle:")):
                return ("export", struct.unpack_from("<i", d, off)[0])
            if typ == "serializationDeferredDataBuffer" or typ == "DataBuffer":
                return ("buffer", struct.unpack_from("<H", d, off)[0])
            if typ in ("String", "NodeRef"):
                # a packed length: bit 7 set means 1-byte characters, bit 6 more length bytes follow
                # (a NodeRef is written the same way: "#name" or "$/path/in/the/world")
                b = d[off]
                ansi = bool(b & 0x80)
                n = b & 0x3F
                p, shift = off + 1, 6
                more = b & 0x40
                while more:
                    nb = d[p]
                    n |= (nb & 0x7F) << shift
                    shift += 7
                    p += 1
                    more = nb & 0x80
                if ansi:
                    return d[p:p + n].decode("utf-8", "replace")
                return d[p:p + 2 * n].decode("utf-16-le", "replace")
            if typ.startswith("array:"):
                inner = typ[6:]
                n = struct.unpack_from("<I", d, off)[0]
                p = off + 4
                out = []
                if inner in FIXED:
                    s = FIXED[inner][1]
                    return [self.val(inner, p + i * s, p + (i + 1) * s) for i in range(n)]
                if inner == "CName" or inner.startswith(("rRef:", "raRef:")):
                    return [self.val(inner, p + i * 2, p + (i + 1) * 2) for i in range(n)]
                if inner.startswith(("handle:", "whandle:")):
                    return [self.val(inner, p + i * 4, p + (i + 1) * 4) for i in range(n)]
                # structs: leading zero then props, zero name terminates
                for _ in range(n):
                    obj = self.read_cr2w_obj(p, end)
                    out.append(obj)
                    p = self.skip_cr2w_obj(p, end)
                return out
            if end - off == 2:
                return self.c.names[struct.unpack_from("<H", d, off)[0]]
            return self.read_cr2w_obj(off, end)
        except Exception as ex:
            return f"<{typ}: {ex}>"

    def skip_cr2w_obj(self, off, end):
        d = self.head
        p = off + 1
        while p + 2 <= end:
            ni = struct.unpack_from("<H", d, p)[0]
            if ni == 0:
                return p + 2
            size = struct.unpack_from("<I", d, p + 4)[0]
            p += 4 + size
        return end

    def buffer(self, index):
        i = (index & 0x3FFF) - 1
        return self.buffers[i] if 0 <= i < len(self.buffers) else None
