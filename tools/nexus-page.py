"""Turns the players' part of a mod's README into the text for its Nexus Mods page.

The players' part runs from the title to "## For developers", as .claude/rules/writing.md lays it out. The result goes
to the mod's dist/nexus-page.txt: the first paragraph as the page's brief overview, then the description in the BBCode
the page takes. A header image is left out, since the page has its own header upload.

    python -I tools/nexus-page.py headset
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def inline(text):
    """Bold stays bold, code becomes plain text, and a link keeps its address only if it's a web address."""
    text = re.sub(r"\*\*(.+?)\*\*", r"[b]\1[/b]", text)
    text = re.sub(r"`([^`]+)`", r"\1", text)

    def link(match):
        label, target = match.group(1), match.group(2)
        return f"[url={target}]{label}[/url]" if re.match(r"https?://", target) else label

    return re.sub(r"(?<!!)\[([^\]]+)\]\(([^)]+)\)", link, text)


def convert(lines):
    """Returns the overview and the description. The source has one sentence per line, so a paragraph's or a list
    item's lines are joined with spaces: on the page a line break shows as one."""
    blocks = []
    paragraph = []
    items = []
    numbered = False
    overview = None

    def flush():
        nonlocal paragraph, items, overview
        if paragraph:
            text = " ".join(paragraph)
            if overview is None:
                overview = text
            blocks.append(inline(text))
            paragraph = []
        if items:
            tag = "[list=1]" if numbered else "[list]"
            body = "\n".join(f"[*]{inline(' '.join(item))}" for item in items)
            blocks.append(f"{tag}\n{body}\n[/list]")
            items = []

    for raw in lines:
        line = raw.rstrip()
        if line.startswith("## For developers"):
            break
        if line.startswith("# ") or re.match(r"!\[[^\]]*\]\([^)]+\)$", line.strip()):
            continue
        if not line.strip():
            flush()
            continue
        heading = re.match(r"#{2,6} (.+)", line)
        bullet = re.match(r"[-*] (.+)", line)
        number = re.match(r"\d+\. (.+)", line)
        if heading:
            flush()
            blocks.append(f"[size=4][b]{inline(heading.group(1))}[/b][/size]")
        elif bullet or number:
            if paragraph:
                flush()
            numbered = bool(number)
            items.append([(bullet or number).group(1)])
        elif items and raw.startswith("  "):
            items[-1].append(line.strip())
        else:
            if items:
                flush()
            paragraph.append(line.strip())
    flush()
    return overview or "", "\n\n".join(blocks)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: python -I tools/nexus-page.py <mod folder name, such as headset>")
    mod = ROOT / "mods" / sys.argv[1]
    overview, description = convert((mod / "README.md").read_text(encoding="utf-8").splitlines())
    out = mod / "dist" / "nexus-page.txt"
    out.parent.mkdir(exist_ok=True)
    out.write_text(
        "=== Brief overview ===\n\n"
        f"{overview}\n\n"
        "=== Description (paste as BBCode) ===\n\n"
        f"{description}\n",
        encoding="utf-8",
    )
    print(out)


if __name__ == "__main__":
    main()
