"""Minimal read-only reader for Cyberpunk 2077 .archive files, using the game's Oodle DLL."""
import ctypes
import mmap
import os
import struct

GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
_oodle = ctypes.WinDLL(os.path.join(GAME, r"bin\x64\oo2ext_7_win64.dll"))
_dec = _oodle.OodleLZ_Decompress
_dec.restype = ctypes.c_longlong
_dec.argtypes = [ctypes.c_char_p, ctypes.c_longlong, ctypes.c_char_p, ctypes.c_longlong,
                 ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_void_p, ctypes.c_longlong,
                 ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_longlong, ctypes.c_int]


def fnv1a64(path):
    v = 0xCBF29CE484222325
    for b in path.lower().replace("/", "\\").encode("utf-8"):
        v = ((v ^ b) * 0x100000001B3) & (2**64 - 1)
    return v


def kraken(buf, size):
    out = ctypes.create_string_buffer(size)
    got = _dec(bytes(buf), len(buf), out, size, 0, 0, 0, None, 0, None, None, None, 0, 3)
    if got != size:
        raise ValueError(f"oodle returned {got}, wanted {size}")
    return out.raw


class Archive:
    def __init__(self, path):
        self.path = path
        self.f = open(path, "rb")
        self.m = mmap.mmap(self.f.fileno(), 0, access=mmap.ACCESS_READ)
        magic, version, idx_pos, idx_size = struct.unpack_from("<4sIQI", self.m, 0)
        if magic != b"RDAR":
            raise ValueError("not an archive")
        p = idx_pos
        _tbl_off, _tbl_size, _crc, n_files, n_segs, n_deps = struct.unpack_from("<IIQIII", self.m, p)
        p += 28
        self.files = {}
        self.entries = []
        for i in range(n_files):
            h, ts, n_inline, s0, s1, d0, d1 = struct.unpack_from("<QqIIIII", self.m, p)
            p += 56
            e = (h, n_inline, s0, s1, d0, d1)
            self.entries.append(e)
            self.files[h] = e
        self.seg_base = p
        p += n_segs * 16
        self.dep_base = p
        self.n_deps = n_deps

    def _seg(self, i):
        return struct.unpack_from("<QII", self.m, self.seg_base + i * 16)

    def read_segment(self, i):
        off, zsize, size = self._seg(i)
        data = self.m[off:off + zsize]
        if zsize == size:
            return bytes(data)
        if data[:4] == b"KARK":
            real = struct.unpack_from("<I", data, 4)[0]
            return kraken(data[8:], real)
        return bytes(data)

    def head(self, h):
        """First segment only: the CR2W without its buffers."""
        e = self.files[h]
        return self.read_segment(e[2])

    def read_all(self, h):
        e = self.files[h]
        return b"".join(self.read_segment(i) for i in range(e[2], e[3]))

    def deps(self, h):
        e = self.files[h]
        return [struct.unpack_from("<Q", self.m, self.dep_base + i * 8)[0] for i in range(e[4], e[5])]


class CR2W:
    """Just the tables: names and imports. Enough to see what a file is and what it uses."""

    def __init__(self, data):
        if data[:4] != b"CR2W":
            raise ValueError("not cr2w")
        self.data = data
        # file header: magic, version, flags, timestamp(8), buildVersion, objectsEnd, buffersEnd, crc, numChunks
        # then 10 table descriptors of (offset, count, crc)
        p = 40
        self.tables = [struct.unpack_from("<III", data, p + i * 12) for i in range(10)]
        str_off, str_size, _ = self.tables[0]
        self.strings = data[str_off:str_off + str_size]
        name_off, name_n, _ = self.tables[1]
        self.names = []
        for i in range(name_n):
            o, _hash = struct.unpack_from("<II", data, name_off + i * 8)
            self.names.append(self._s(o))
        imp_off, imp_n, _ = self.tables[2]
        self.imports = []
        for i in range(imp_n):
            o, cls, flags = struct.unpack_from("<IHH", data, imp_off + i * 8)
            self.imports.append((self._s(o), self.names[cls] if cls < len(self.names) else "?", flags))
        exp_off, exp_n, _ = self.tables[4]
        self.exports = []
        for i in range(exp_n):
            cls = struct.unpack_from("<H", data, exp_off + i * 24)[0]
            self.exports.append(self.names[cls] if cls < len(self.names) else "?")

    def _s(self, o):
        e = self.strings.find(b"\0", o)
        return self.strings[o:e].decode("utf-8", "replace")
