"""Read NightCoop.dll's disassembly: its script natives, functions, and the strings they use.

NightCoop is closed source; this is how its script-callable natives and their
signatures were found (see RECORD.md). Commands:

  disasm             write build/NightCoop.asm with llvm-objdump (needed by the rest)
  natives            every native PostRegisterTypes registers, with its signature
  fn ADDR            a function's disassembly, .rdata strings shown inline
  strings ADDR       the strings a function and its callees use (--depth)
  where ADDR         the function holding ADDR, its strings, and who calls it
  xref TEXT          where a string sits and which code loads it

ADDR is hex, as llvm-objdump prints it (180b46ff0). Run with `python -I`: it
reads the DLL as data only.
"""
import argparse
import bisect
import os
import re
import struct
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
DEFAULT_DLL = os.path.join(GAME, r"red4ext\plugins\NightCoop\NightCoop.dll")
DEFAULT_ASM = os.path.join(REPO, "build", "NightCoop.asm")

LINE = re.compile(r"^\s*([0-9a-f]+):\s+(\S+)\s*(.*?)\s*$")
LABEL = re.compile(r"^([0-9a-f]{16}) <([^>]+)>:$")
TARGET = re.compile(r"#\s*0x([0-9a-f]+)")


class Image:
    """The DLL's bytes and sections, to turn an address into the string stored there."""

    def __init__(self, path):
        self.data = open(path, "rb").read()
        pe = struct.unpack_from("<I", self.data, 0x3C)[0]
        count = struct.unpack_from("<H", self.data, pe + 6)[0]
        optional = struct.unpack_from("<H", self.data, pe + 20)[0]
        base = struct.unpack_from("<Q", self.data, pe + 24 + 24)[0]
        self.sections = []
        for i in range(count):
            at = pe + 24 + optional + 40 * i
            name = self.data[at:at + 8].rstrip(b"\0").decode()
            size, va, raw_size, raw = struct.unpack_from("<IIII", self.data, at + 8)
            self.sections.append((name, base + va, max(size, raw_size), raw))

    def string(self, va, minimum=3):
        for name, start, size, raw in self.sections:
            if name in (".rdata", ".data") and start <= va < start + size:
                off = va - start + raw
                end = self.data.find(b"\0", off, off + 600)
                text = self.data[off:end]
                if len(text) >= minimum and all(32 <= c < 127 or c >= 0xC0 for c in text):
                    return text.decode("utf-8", "replace")
                return None
        return None

    def address_of(self, text):
        needle = b"\0" + text.encode() + b"\0"
        found = []
        at = self.data.find(needle)
        while at >= 0:
            off = at + 1
            for name, start, size, raw in self.sections:
                if raw <= off < raw + size:
                    found.append(start + off - raw)
            at = self.data.find(needle, at + 1)
        return found


class Listing:
    """llvm-objdump's text, indexed by address."""

    def __init__(self, path):
        if not os.path.exists(path):
            sys.exit(f"no disassembly at {path}: run `ncre.py disasm` first")
        self.addrs, self.ops, self.labels = [], [], {}
        for raw in open(path, encoding="utf-8-sig", errors="replace"):
            label = LABEL.match(raw.strip())
            if label:
                self.labels[label.group(2)] = int(label.group(1), 16)
                continue
            m = LINE.match(raw)
            if m:
                self.addrs.append(int(m.group(1), 16))
                self.ops.append((m.group(2), m.group(3)))

    def index(self, addr):
        return bisect.bisect_left(self.addrs, addr)

    def function(self, addr):
        """(start, end) indexes of the function holding addr, bounded by int3 padding."""
        i = self.index(addr)
        start = i
        while start > 0 and self.ops[start - 1][0] != "int3":
            start -= 1
        end = i
        while end < len(self.ops) and self.ops[end][0] != "int3":
            end += 1
        return start, end

    def body(self, addr):
        for i in range(self.index(addr), len(self.ops)):
            yield i
            op = self.ops[i][0]
            if op == "int3" or op.startswith("ret"):
                return


def target(args):
    t = TARGET.search(args)
    return int(t.group(1), 16) if t else None


def cmd_disasm(opts):
    os.makedirs(os.path.dirname(opts.asm), exist_ok=True)
    with open(opts.asm, "w", encoding="utf-8") as out:
        subprocess.run(["llvm-objdump", "-d", "--no-show-raw-insn", "--section=.text", opts.dll], stdout=out, check=True)
    print(f"wrote {opts.asm}")


def cmd_natives(opts):
    """Each registration loads type-name strings into callee-saved registers, lays the
    parameter types out on the stack, and calls a helper with rcx = name,
    rdx = native, r8 = return type and r9 = the parameter list."""
    image, listing = Image(opts.dll), Listing(opts.asm)
    start = listing.labels.get("PostRegisterTypes")
    if start is None:
        sys.exit("no PostRegisterTypes in the disassembly")
    after = [a for a in listing.labels.values() if a > start]
    end = min(after) if after else listing.addrs[-1]

    regs, stack = {}, {}
    name = native = ret = None
    params = None  # [begin, end] rbp offsets of the parameter list, or "none"
    for i in range(listing.index(start), listing.index(end)):
        op, args = listing.ops[i]
        text = image.string(target(args)) if target(args) else None
        lea = re.match(r"-?0x[0-9a-f]+\(%rip\), %(\w+)", args)
        if op == "leaq" and lea:
            reg = lea.group(1)
            if reg == "rcx" and text:
                name = text
            elif reg == "rdx":
                native = target(args)
            elif text:
                regs[reg] = text
            continue
        store = re.match(r"%(\w+), (-?0x[0-9a-f]+)\(%rbp\)$", args)
        if op == "movq" and store and store.group(1) in regs:
            stack[int(store.group(2), 16)] = regs[store.group(1)]
            continue
        to_r8 = re.match(r"%(\w+), %r8$", args)
        if op == "movq" and to_r8:
            ret = regs.get(to_r8.group(1), "?")
            continue
        bound = re.match(r"(-?0x[0-9a-f]+)\(%rbp\), %rax$", args)
        if op == "leaq" and bound:
            off = int(bound.group(1), 16)
            params = [params[0], off] if isinstance(params, list) and params[1] is None else [off, None]
            continue
        if op == "movdqa" and "-0x40(%rbp)" in args:
            params = "none"
            continue
        if op == "callq" and name:
            types = []
            if isinstance(params, list) and params[1] is not None:
                types = [stack.get(off, "?") for off in range(params[0], params[1], 8)]
            if name.startswith("NightCoop") or opts.all:
                where = f"  @{native:x}" if native else ""
                print(f"{name}({', '.join(types)}) -> {ret}{where}")
            name = native = ret = None
            params = None


def cmd_fn(opts):
    image, listing = Image(opts.dll), Listing(opts.asm)
    for n, i in enumerate(listing.body(int(opts.addr, 16))):
        op, args = listing.ops[i]
        line = f"{listing.addrs[i]:x}:  {op}\t{args}"
        t = target(args)
        text = image.string(t) if t else None
        if text:
            line += f'   "{text[:160]}"'
        print(line)
        if n >= opts.limit:
            break


def cmd_strings(opts):
    image, listing = Image(opts.dll), Listing(opts.asm)
    text_section = next(s for s in image.sections if s[0] == ".text")
    seen, queue = set(), [(int(opts.addr, 16), 0)]
    while queue and len(seen) < opts.max:
        fn, level = queue.pop(0)
        if fn in seen:
            continue
        seen.add(fn)
        found = []
        for i in listing.body(fn):
            op, args = listing.ops[i]
            t = target(args)
            text = image.string(t, 4) if t else None
            if text and text not in found:
                found.append(text)
            if level < opts.depth:
                call = re.match(r"0x([0-9a-f]+)", args) if op == "callq" else None
                if call:
                    queue.append((int(call.group(1), 16), level + 1))
                # natives hand their work to a callback loaded with lea
                if op == "leaq" and t and text_section[1] <= t < text_section[1] + text_section[2]:
                    queue.append((t, level + 1))
        if found:
            print(f"== {fn:x} (depth {level})")
            for text in found:
                print("   " + text[:240])


def cmd_where(opts):
    image, listing = Image(opts.dll), Listing(opts.asm)
    start, end = listing.function(int(opts.addr, 16))
    fn = listing.addrs[start]
    print(f"function {fn:x} .. {listing.addrs[end - 1]:x}")
    for i in range(start, end):
        t = target(listing.ops[i][1])
        text = image.string(t, 2) if t else None
        if text:
            print(f"  {listing.addrs[i]:x}: {text[:200]}")
    needle = f"0x{fn:x}"
    callers = [listing.addrs[i] for i, (op, args) in enumerate(listing.ops) if needle in args and op in ("callq", "jmp", "leaq")]
    print("referenced from:", ", ".join(f"{c:x}" for c in callers[:20]) or "nothing direct")


def cmd_xref(opts):
    image, listing = Image(opts.dll), Listing(opts.asm)
    for va in image.address_of(opts.text):
        print(f"string at {va:x}")
        needle = f"0x{va:x}"
        for i, (op, args) in enumerate(listing.ops):
            if needle in args:
                print(f"  loaded at {listing.addrs[i]:x}: {op} {args}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dll", default=DEFAULT_DLL)
    parser.add_argument("--asm", default=DEFAULT_ASM)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("disasm").set_defaults(run=cmd_disasm)
    natives = sub.add_parser("natives")
    natives.add_argument("--all", action="store_true", help="include the short console aliases")
    natives.set_defaults(run=cmd_natives)
    fn = sub.add_parser("fn")
    fn.add_argument("addr")
    fn.add_argument("--limit", type=int, default=400)
    fn.set_defaults(run=cmd_fn)
    strings = sub.add_parser("strings")
    strings.add_argument("addr")
    strings.add_argument("--depth", type=int, default=2)
    strings.add_argument("--max", type=int, default=40, help="functions to visit at most")
    strings.set_defaults(run=cmd_strings)
    where = sub.add_parser("where")
    where.add_argument("addr")
    where.set_defaults(run=cmd_where)
    xref = sub.add_parser("xref")
    xref.add_argument("text")
    xref.set_defaults(run=cmd_xref)
    opts = parser.parse_args()
    # NightCoop's strings hold non-ASCII text; a Windows console can't print all of it
    sys.stdout.reconfigure(errors="replace")
    opts.run(opts)


if __name__ == "__main__":
    main()
