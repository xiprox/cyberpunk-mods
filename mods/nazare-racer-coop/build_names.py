"""Builds the archive holding the names of the Nazare "Racer" copies.

A TweakXL record can only point at a text key, so new text has to come from a
localization file inside an .archive. This writes that file and that archive
with no modding tools, using only the game's own compression DLL.

    python -I build_names.py                 writes archive/pc/mod/nazareracercopies_names/nazareracercopies.archive
    python -I build_names.py --check         checks the writer against real mod files

The format was read from working mods, and --check holds it to them: it rebuilds
the kart mod's localization file byte for byte, and recomputes the checksum of
real archives. To change a name, edit NAMES and build again.
"""

import ctypes
import os
import struct
import sys
import zlib

GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
OODLE = os.path.join(GAME, r"bin\x64\oo2ext_7_win64.dll")

# Where the file sits inside the archive; the .xl names this same path.
DEPOT_PATH = r"nazare_racer_coop\names.json"

NAMES = [
    ("nazare_racer_kuro_name", 'Nazar\u00e9 "Racer" Kuro'),
    ("nazare_racer_shiro_name", 'Nazar\u00e9 "Racer" Shiro'),
]

# The file's table of names, with the hashes real localization files store for them.
CR2W_NAMES = [
    ("", 0),
    ("JsonResource", 0xCA709639),
    ("root", 0x53909ADA),
    ("handle:ISerializable", 0x9BDAB64F),
    ("localizationPersistenceOnScreenEntries", 0x9D45781E),
    ("entries", 0xCDF7057F),
    ("array:localizationPersistenceOnScreenEntry", 0x4933733A),
    ("secondaryKey", 0x8B47E483),
    ("String", 0x8C5FD1D4),
    ("femaleVariant", 0xAE8C42F1),
]
ROOT, HANDLE, ENTRIES, ENTRY_ARRAY, SECONDARY_KEY, STRING, FEMALE_VARIANT = 2, 3, 5, 6, 7, 8, 9
JSON_RESOURCE, ON_SCREEN_ENTRIES = 1, 4


def path_hash(path):
    """FNV-1a 64 of the lower-case path, which is how an archive names its files."""
    value = 0xCBF29CE484222325
    for byte in path.lower().encode("ascii"):
        value = ((value ^ byte) * 0x100000001B3) & (2**64 - 1)
    return value


def crc64(data):
    """CRC-64/XZ, which the index of a .archive is checked with."""
    table = crc64.table
    value = 2**64 - 1
    for byte in data:
        value = table[(value ^ byte) & 0xFF] ^ (value >> 8)
    return value ^ (2**64 - 1)


def _crc64_table():
    table = []
    for i in range(256):
        value = i
        for _ in range(8):
            value = (value >> 1) ^ 0xC96C5795D7870F42 if value & 1 else value >> 1
        table.append(value)
    return table


crc64.table = _crc64_table()


def red_string(text):
    """A string property: its size, then a length byte (0x80 marks UTF-8), then the bytes."""
    data = text.encode("utf-8")
    if len(data) < 0x40:
        prefix = bytes([0x80 | len(data)])
    else:
        prefix = bytes([0xC0 | (len(data) & 0x3F), len(data) >> 6])
    return struct.pack("<I", 4 + len(prefix) + len(data)) + prefix + data


def string_prop(name, text):
    return struct.pack("<HH", name, STRING) + red_string(text)


def localization_cr2w(entries):
    """The localization file, a CR2W holding a JsonResource and its list of entries."""
    table = bytearray()
    names = bytearray()
    for name, name_hash in CR2W_NAMES:
        names += struct.pack("<II", len(table), name_hash)
        table += name.encode("ascii") + b"\0"

    values = struct.pack("<I", len(entries))
    for key, text in entries:
        values += b"\0" + string_prop(SECONDARY_KEY, key) + string_prop(FEMALE_VARIANT, text) + b"\0\0"
    list_chunk = b"\0" + struct.pack("<HHI", ENTRIES, ENTRY_ARRAY, 4 + len(values)) + values + b"\0\0"
    root_chunk = b"\0" + struct.pack("<HHII", ROOT, HANDLE, 8, 2) + b"\0\0"

    properties = bytes(16)
    headers = 160
    names_at = headers + len(table)
    properties_at = names_at + len(names)
    exports_at = properties_at + len(properties)
    root_at = exports_at + 2 * 24
    list_at = root_at + len(root_chunk)
    end = list_at + len(list_chunk)
    exports = struct.pack("<HHIIIII", JSON_RESOURCE, 0, 0, len(root_chunk), root_at, 0, 0)
    exports += struct.pack("<HHIIIII", ON_SCREEN_ENTRIES, 0, 0, len(list_chunk), list_at, 0, 0)

    tables = [
        (headers, len(table), zlib.crc32(table)),
        (names_at, len(CR2W_NAMES), zlib.crc32(names)),
        (0, 0, 0),
        (properties_at, 1, zlib.crc32(properties)),
        (exports_at, 2, zlib.crc32(exports)),
    ] + [(0, 0, 0)] * 5
    table_bytes = b"".join(struct.pack("<III", *entry) for entry in tables)

    def header(crc):
        return b"CR2W" + struct.pack("<IIQIIIII", 195, 0, 0, 0, end, end, crc, 6)

    crc = zlib.crc32(header(0xDEADBEEF) + table_bytes)
    return header(crc) + table_bytes + bytes(table) + bytes(names) + properties + exports + root_chunk + list_chunk


def kraken(data):
    """Compresses as every CR2W in a mod archive is: "KARK", the raw size, Oodle Kraken."""
    oodle = ctypes.WinDLL(OODLE)
    compress = oodle.OodleLZ_Compress
    compress.restype = ctypes.c_longlong
    compress.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_longlong, ctypes.c_char_p, ctypes.c_int] + [ctypes.c_void_p] * 3 + [ctypes.c_void_p, ctypes.c_longlong]
    out = ctypes.create_string_buffer(len(data) + 65536)
    size = compress(8, data, len(data), out, 4, None, None, None, None, 0)
    if size <= 0:
        raise RuntimeError("Oodle couldn't compress the file")
    return b"KARK" + struct.pack("<I", len(data)) + out.raw[:size]


def kraken_undo(stored, size):
    oodle = ctypes.WinDLL(OODLE)
    decompress = oodle.OodleLZ_Decompress
    decompress.restype = ctypes.c_longlong
    decompress.argtypes = [ctypes.c_char_p, ctypes.c_longlong, ctypes.c_char_p, ctypes.c_longlong] + [ctypes.c_int] * 3 + [ctypes.c_void_p, ctypes.c_longlong] + [ctypes.c_void_p] * 3 + [ctypes.c_longlong, ctypes.c_int]
    out = ctypes.create_string_buffer(size)
    done = decompress(stored[8:], len(stored) - 8, out, size, 0, 0, 0, None, 0, None, None, None, 0, 3)
    if done != size:
        raise RuntimeError("Oodle couldn't read the file back")
    return out.raw


def archive(depot_path, cr2w):
    """A .archive of one file: the header, the file, then the index on a 4 KB boundary."""
    stored = kraken(cr2w)
    data_at = 0xAC  # the header, then what's reserved after it; every mod archive starts here
    index_at = (data_at + len(stored) + 0xFFF) & ~0xFFF

    empty_sha1 = bytes.fromhex("da39a3ee5e6b4b0d3255bfef95601890afd80709")  # what real archives hold
    record = struct.pack("<QQIIIII", path_hash(depot_path), 133992325147125702, 0, 0, 1, 0, 0) + empty_sha1
    segment = struct.pack("<QII", data_at, len(stored), len(cr2w))
    body = struct.pack("<III", 1, 1, 0) + record + segment
    index = struct.pack("<IIQ", 8, 8 + len(body), crc64(body)) + body
    size = (index_at + len(index) + 0xFFF) & ~0xFFF

    head = b"RDAR" + struct.pack("<IQIQIQ", 12, index_at, len(index), 0, 0, size) + bytes(8)
    return (head.ljust(data_at, b"\0") + stored).ljust(index_at, b"\0") + index.ljust(size - index_at, b"\0")


def check():
    mods = os.path.join(GAME, r"archive\pc\mod")
    with open(os.path.join(mods, "kart.archive"), "rb") as f:
        kart = f.read()
    index_at, = struct.unpack_from("<Q", kart, 8)
    files, segments, _ = struct.unpack_from("<III", kart, index_at + 16)
    wanted = path_hash(r"oranje3\kart\oranje3_kart.json")
    first = index_at + 28
    for i in range(files):
        if struct.unpack_from("<Q", kart, first + 56 * i)[0] == wanted:
            start, = struct.unpack_from("<I", kart, first + 56 * i + 20)
            at, stored, size = struct.unpack_from("<QII", kart, first + 56 * files + 16 * start)
            real = kraken_undo(kart[at:at + stored], size)
    entries = [
        ("oranje3_kart_name", "Cyber Kart"),
        ("oranje3_kart_info", "Born out of the mind of a mentalist, this pocket rocket is a Makigai MaiMai stripped to the bare racing core. You'd never believe this insane little racer was hiding beneath the fugly outer shell of the much loved micro car. Hold on tight, it's one hell of a drive!"),
        ("oranje3_kart_year", "2075"),
    ]
    rebuilt = localization_cr2w(entries)
    print("kart's localization file rebuilt byte for byte:", rebuilt == real)
    if rebuilt != real:
        for i, (a, b) in enumerate(zip(rebuilt, real)):
            if a != b:
                print("  first difference at", i, "of", len(real), len(rebuilt), rebuilt[max(0, i - 8):i + 8], real[max(0, i - 8):i + 8])
                break

    for name in ("!NoMoreMenuBackgrounds.archive", "###-BlurBegone-OpticalCamo.archive", "VirtualCarDealer.archive"):
        with open(os.path.join(mods, name), "rb") as f:
            data = f.read()
        at, size = struct.unpack_from("<QI", data, 8)
        print(name, "index checksum matches:", crc64(data[at + 16:at + size]) == struct.unpack_from("<Q", data, at + 8)[0])

    built = archive(DEPOT_PATH, localization_cr2w(NAMES))
    at, size = struct.unpack_from("<QI", built, 8)
    segment_at, stored, raw = struct.unpack_from("<QII", built, at + 28 + 56)
    back = kraken_undo(built[segment_at:segment_at + stored], raw)
    print("our archive reads back to our file:", back == localization_cr2w(NAMES))
    print("our archive: file hash matches path:", struct.unpack_from("<Q", built, at + 28)[0] == path_hash(DEPOT_PATH))
    print("our archive: index checksum matches:", crc64(built[at + 16:at + size]) == struct.unpack_from("<Q", built, at + 8)[0])
    print("our archive: size field matches:", struct.unpack_from("<Q", built, 32)[0] == len(built), len(built))
    return rebuilt == real


def main():
    if "--check" in sys.argv:
        sys.exit(0 if check() else 1)
    target = os.path.join(os.path.dirname(os.path.abspath(__file__)), "archive", "pc", "mod", "nazareracercopies_names", "nazareracercopies.archive")
    with open(target, "wb") as f:
        f.write(archive(DEPOT_PATH, localization_cr2w(NAMES)))
    print("wrote", target)


main()
