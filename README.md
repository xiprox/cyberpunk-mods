# Cyberpunk 2077 mods

Our mods for Cyberpunk 2077, most of them for playing co-op on NightCoop.
Each mod's own README says how it's built and installed, and its RECORD.md (where it has one) what we found and decided.

| Folder | What |
|---|---|
| `mods/nightcoop-voice` | Proximity and radio voice for NightCoop |
| `mods/nightcoop-tweaks` | Cyber Engine Tweaks additions to NightCoop: the partner menu, sending money, bike seats |
| `mods/vehicle-customizer` | Customize cars and bikes, seen by co-op partners |
| `mods/nazare-racer-coop` | Racer copies, so two players can each ride one in NightCoop |
| `mods/passenger-radio` | The radio key the passenger seat lacks |
| `mods/no-carry-weight` | Adds 1000 carry capacity |
| `vendor/nightcoop-sdk` | NightCoop's SDK and its docs (MIT), which the mods build against |
| `tools/` | What more than one mod uses, or isn't about any one mod |

## Shared tools

Compile a mod's redscript without touching the game, safe while it runs:

```bash
powershell -File tools/check-scripts.ps1 -Mod nightcoop-voice
```

```bash
powershell -File tools/check-scripts.ps1 -Mod vehicle-customizer
```

Read NightCoop's DLL for its natives (`disasm` first; needs `llvm-objdump`):

```bash
python -I tools/ncre.py --help
```

A mod's own tools are in its `tools/` folder.
