# Draws the mode wheel's art and packs it into game/archive/headset/headset_wheel.archive.
# White, tinted in the game, with its colour already multiplied by its alpha: that's how the game's UI blends, and plain white over
# alpha 0 came out as solid squares. One slice is drawn and turned by the script, so all three are the same shape.
#   python -I tools/make_wheel_art.py
# Needs WolvenKit's command line. The texture and atlas start from the game's own wheel highlight, so they keep its UI settings.

import json
import math
import pathlib
import shutil
import struct
import subprocess
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / "build" / "art"
OUT = ROOT / "game" / "archive" / "headset"
GAME_ARCHIVES = pathlib.Path(r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\archive\pc\content")
WOLVENKIT = r"H:\WolvenKit\Console\WolvenKit.CLI.exe"
DEPOT = pathlib.PurePosixPath("headset/wheel")

CELL = 1024  # each wheel part is one square, centred on the wheel, so turning the widget turns it about the wheel's centre
WIDTH = CELL * 4
HEIGHT = CELL * 2
HALF_UNITS = 640.0  # half a wheel part's side in the game's UI units; HeadsetWheel.reds has the same numbers
T = (CELL / 2) / HALF_UNITS  # texels per UI unit

OUTER = 540.0 * T
INNER = 104.0 * T
GAP = 8.0 * T
CHAMFER = 40.0 * T
LINE = 2.6
RIM = 9.6
RING = 572.0 * T
RING_LINE = 2.4
POINTER_LINE = 6.4
POINTER_HALF_DEGREES = 14.0

WAVE_WIDTH = 340
WAVE_HEIGHT = 170
PANEL_WIDTH = 473  # 620 x 560 in UI units, at the same scale as HeadsetWheel.reds' panel
PANEL_HEIGHT = 427
PANEL_CHAMFER = 36.0

BISECTOR = math.radians(60.0)
FOLD_X, FOLD_Y = math.cos(BISECTOR), -math.sin(BISECTOR)


def coverage(distance):
    return max(0.0, min(1.0, 0.5 - distance))


def fold(x, y):
    # A slice is mirror-symmetric about its middle, so everything past the middle is measured as its mirror image.
    side = x * FOLD_X + y * FOLD_Y
    if side > 0.0:
        x -= 2.0 * side * FOLD_X
        y -= 2.0 * side * FOLD_Y
    return x, y


def chamfer_line():
    start = (GAP, math.sqrt((OUTER - CHAMFER) ** 2 - GAP**2))
    angle = math.asin(GAP / OUTER) + CHAMFER / OUTER
    end = (OUTER * math.sin(angle), OUTER * math.cos(angle))
    nx, ny = end[1] - start[1], -(end[0] - start[0])
    length = math.hypot(nx, ny)
    nx, ny = nx / length, ny / length
    if (GAP - start[0]) * nx + (OUTER - start[1]) * ny < 0.0:
        nx, ny = -nx, -ny
    return start, nx, ny


CHAMFER_START, CHAMFER_NX, CHAMFER_NY = chamfer_line()


def slice_distance(x, y):
    # Negative inside a slice from straight up to 120 degrees clockwise, its straight edges a constant GAP from the seam.
    radius = math.hypot(x, y)
    fx, fy = fold(x, y)
    cut = (fx - CHAMFER_START[0]) * CHAMFER_NX + (fy - CHAMFER_START[1]) * CHAMFER_NY
    return max(radius - OUTER, INNER - radius, GAP - fx, cut)


def part_fill(x, y):
    return coverage(slice_distance(x, y))


def part_glow(x, y):
    amount = max(0.0, min(1.0, (math.hypot(x, y) - 0.35 * OUTER) / (0.65 * OUTER)))
    return coverage(slice_distance(x, y)) * amount**1.6


def part_line(x, y):
    return coverage(abs(slice_distance(x, y) + LINE / 2) - LINE / 2)


def part_rim(x, y):
    band = abs(math.hypot(x, y) - (OUTER - RIM / 2)) - RIM / 2
    return coverage(max(band, slice_distance(x, y)))


def part_ring(x, y):
    radius = math.hypot(x, y)
    if radius < RING - 3.0:
        return 0.0
    angle = math.degrees(math.atan2(x, y)) % 360.0
    best = 0.0
    if abs((angle + 60.0) % 120.0 - 60.0) >= 6.0:
        best = coverage(abs(radius - RING) - RING_LINE / 2)
    tick = round(angle / 10.0) * 10
    if tick % 120 != 0:
        across = abs(radius * math.sin(math.radians(angle - tick))) - 1.2
        length = 25.6 if tick % 30 == 0 else 16.0
        best = max(best, coverage(max(across, RING + 6.4 - radius, radius - (RING + length))))
    return best


def part_pointer(x, y):
    radius = math.hypot(x, y)
    off_angle = abs(math.degrees(math.atan2(x, y))) - POINTER_HALF_DEGREES
    return coverage(max(abs(radius - RING) - POINTER_LINE / 2, radius * math.radians(off_angle)))


def rounded_box(x, y, half_w, half_h, radius):
    qx = abs(x) - (half_w - radius)
    qy = abs(y) - (half_h - radius)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - radius


def part_headphones(x, y):
    # The HUD's icon: a band over the top, and an ear cup at each end of it.
    middle = -10.0
    band = max(abs(math.hypot(x, y - middle) - 84.0) - 7.0, middle - y)
    cups = min(rounded_box(x - 84.0, y - (middle - 32.0), 17.0, 40.0, 10.0), rounded_box(x + 84.0, y - (middle - 32.0), 17.0, 40.0, 10.0))
    return coverage(min(band, cups))


def wave_height(mode, u):
    # In the mockup's pixels, from which the shapes were approved.
    v = math.sin(u * math.pi * 6.0)
    if mode == 0:
        return v * 22.0
    if mode == 1:
        # Quiet at the ends and loud in the middle, smoothly, with the loud part's peaks cut flat.
        return max(-13.0, min(13.0, v * (12.0 + 22.0 * math.sin(u * math.pi) ** 2)))
    return v * (22.0 * (1.0 - u) * (1.0 - u) + 1.5)


def part_wave(mode):
    span = WAVE_WIDTH - 40.0
    scale = span / 96.0

    def shape(x, y):
        u = (x + span / 2.0) / span
        if u < -0.05 or u > 1.05:
            return 0.0
        # The nearest of closely spaced points along the curve: exact enough, and clean at the corners where the peaks are cut.
        best = 1e9
        for k in range(-24, 25):
            point = max(0.0, min(1.0, u + k * 0.002))
            best = min(best, math.hypot(x - (point - 0.5) * span, y - scale * wave_height(mode, point)))
        return coverage(best - 3.2)

    return shape


def panel_distance(x, y):
    half_w = PANEL_WIDTH / 2.0 - 1.0
    half_h = PANEL_HEIGHT / 2.0 - 1.0
    cut = ((x - half_w) + (-half_h - y) + PANEL_CHAMFER) / math.sqrt(2.0)
    return max(abs(x) - half_w, abs(y) - half_h, cut)


def part_panel_fill(x, y):
    return coverage(panel_distance(x, y))


def part_panel_line(x, y):
    return coverage(abs(panel_distance(x, y) + 1.2) - 1.2)


PANELS_X = CELL * 3
PANELS_Y = CELL
# Name, left, top, width, height, shape.
PARTS = [
    ("fill", 0, 0, CELL, CELL, part_fill),
    ("glow", CELL, 0, CELL, CELL, part_glow),
    ("line", CELL * 2, 0, CELL, CELL, part_line),
    ("rim", CELL * 3, 0, CELL, CELL, part_rim),
    ("ring", 0, CELL, CELL, CELL, part_ring),
    ("pointer", CELL, CELL, CELL, CELL, part_pointer),
    ("headphones", CELL * 2, CELL, 256, 256, part_headphones),
    ("wave0", PANELS_X, PANELS_Y, WAVE_WIDTH, WAVE_HEIGHT, part_wave(0)),
    ("wave1", PANELS_X + 341, PANELS_Y, WAVE_WIDTH, WAVE_HEIGHT, part_wave(1)),
    ("wave2", PANELS_X + 682, PANELS_Y, WAVE_WIDTH, WAVE_HEIGHT, part_wave(2)),
    ("panel_fill", PANELS_X, PANELS_Y + 180, PANEL_WIDTH, PANEL_HEIGHT, part_panel_fill),
    ("panel_line", PANELS_X + 512, PANELS_Y + 180, PANEL_WIDTH, PANEL_HEIGHT, part_panel_line),
]


def write_png(path, alpha):
    raw = bytearray()
    for row in range(HEIGHT):
        raw.append(0)
        line = alpha[row * WIDTH : (row + 1) * WIDTH]
        pixels = bytearray(WIDTH * 4)
        pixels[0::4] = line
        pixels[1::4] = line
        pixels[2::4] = line
        pixels[3::4] = line
        raw += pixels

    def chunk(name, data):
        return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data))

    header = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 6, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))


def draw():
    alpha = bytearray(WIDTH * HEIGHT)
    for _, left, top, width, height, shape in PARTS:
        for py in range(height):
            y = height / 2 - (py + 0.5)
            line = (top + py) * WIDTH + left
            for px in range(width):
                value = shape(px + 0.5 - width / 2, y)
                if value > 0.0:
                    alpha[line + px] = int(value * 255.0 + 0.5)
    return alpha


def wolvenkit(*args, must_say=None):
    result = subprocess.run([WOLVENKIT, *args, "-v", "Minimal"], capture_output=True, text=True)
    # Importing with -k exits 3 even when it worked, so that step goes by what it says.
    failed = must_say not in result.stdout if must_say else result.returncode != 0
    if failed or ": Error" in result.stdout or "Failed" in result.stdout:
        sys.exit(f"WolvenKit {args[0]} failed:\n{result.stdout}\n{result.stderr}")


def make_not_streamable(texture):
    # The import turns streaming on. The game's UI picture has it off, and a wheel has to be sharp the moment it opens.
    wolvenkit("convert", "serialize", str(texture), "-o", str(WORK))
    source = WORK / "wheel.xbm.json"
    data = json.loads(source.read_text(encoding="utf-8"))
    data["Data"]["RootChunk"]["setup"]["isStreamable"] = 0
    source.write_text(json.dumps(data, indent=2), encoding="utf-8")
    wolvenkit("convert", "deserialize", str(source), "-o", str(texture.parent))


def templates():
    # The game's wheel highlight, which is a full-screen UI picture with no mips: the settings this texture wants.
    folder = WORK / "templates"
    if not (folder / "base/gameplay/gui/widgets/radial_wheel/radial_highlight.xbm").exists() or not (
        folder / "base/gameplay/gui/widgets/radial_wheel/radial_highloght.inkatlas"
    ).exists():
        folder.mkdir(parents=True, exist_ok=True)
        for archive in ("basegame_1_engine.archive", "basegame_4_gamedata.archive"):
            wolvenkit("unbundle", str(GAME_ARCHIVES / archive), "-o", str(folder), "-r", r"radial_wheel.radial_(highlight\.xbm|highloght\.inkatlas)$")
    return folder / "base/gameplay/gui/widgets/radial_wheel"


def make_atlas(template, destination):
    wolvenkit("convert", "serialize", str(template / "radial_highloght.inkatlas"), "-o", str(WORK))
    data = json.loads((WORK / "radial_highloght.inkatlas.json").read_text(encoding="utf-8"))
    mappers = []
    for name, left, top, width, height, _ in PARTS:
        mappers.append(
            {
                "$type": "inkTextureAtlasMapper",
                "clippingRectInPixels": {"$type": "Rect", "bottom": 0, "left": 0, "right": 0, "top": 0},
                "clippingRectInUVCoords": {
                    "$type": "RectF",
                    "Bottom": (top + height) / HEIGHT,
                    "Left": left / WIDTH,
                    "Right": (left + width) / WIDTH,
                    "Top": top / HEIGHT,
                },
                "partName": {"$type": "CName", "$storage": "string", "$value": name},
            }
        )
    # One slot for each screen size the game picks between; they all use the one texture.
    for slot in data["Data"]["RootChunk"]["slots"]["Elements"]:
        slot["parts"] = mappers
        # The template's later slots hold a hash here, so the storage has to say this one is a name.
        slot["texture"]["DepotPath"] = {"$type": "ResourcePath", "$storage": "string", "$value": str(DEPOT / "wheel.xbm").replace("/", "\\")}
    source = WORK / "wheel.inkatlas.json"
    source.write_text(json.dumps(data, indent=2), encoding="utf-8")
    wolvenkit("convert", "deserialize", str(source), "-o", str(destination))


def main():
    pack = WORK / "headset_wheel"
    raw = WORK / "raw"
    for folder in (pack, raw):
        if folder.exists():
            shutil.rmtree(folder)
    (pack / DEPOT).mkdir(parents=True)
    (raw / DEPOT).mkdir(parents=True)

    print("drawing")
    write_png(raw / DEPOT / "wheel.png", draw())

    template = templates()
    shutil.copy(template / "radial_highlight.xbm", pack / DEPOT / "wheel.xbm")
    print("texture")
    wolvenkit("import", str(raw), "-o", str(pack), "-k", must_say="Imported 1/1")
    make_not_streamable(pack / DEPOT / "wheel.xbm")
    print("atlas")
    make_atlas(template, pack / DEPOT)

    print("pack")
    OUT.mkdir(parents=True, exist_ok=True)
    wolvenkit("pack", str(pack), "-o", str(OUT))
    built = OUT / "headset_wheel.archive"
    print(built, built.stat().st_size)


if __name__ == "__main__":
    main()
