# VCarve Pro Gadgets

Custom Lua gadgets for VCarve Pro (developed against V10.516) — Prickly Guy Creations.

Each gadget lives in its own `PGC_*` folder, matching the folder/file naming
used in the installed VCarve Gadgets directory. The `.lua` file directly in a
gadget's folder is the current, working version — copy that folder into your
VCarve Gadgets folder to use it. If the gadget has an options dialog, its
matching `.htm` file must be copied alongside the `.lua` file (same folder) —
the script loads the `.htm` from its own folder at runtime. Anything
superseded moves into that gadget's `archive/` folder instead of being
deleted, so there's always a record of what changed and why.

## Gadgets

| Gadget | What it does |
|---|---|
| [`PGC_Rotate`](PGC_Rotate/) | `PGC_RotateAngle.lua` — Rotates every selected object about its own center by an angle you enter in a dialog (defaults to the last angle used). Replaces the old fixed 90°/180° gadgets. |
| [`PGC_Replace_Circles`](PGC_Replace_Circles/) | `PGC_Replace_Circles.lua` — Replaces selected circles with copies of a grouped template object, centered on each original circle. A dialog lets you choose whether to keep the original template after replacement. |
| [`PGC_Count_Selected_Objects`](PGC_Count_Selected_Objects/) | `PGC_Count_Selected_Objects.lua` — Counts selected vectors matching the last-selected object, rotation/translation/direction independent, and flags duplicates at the same location. A dialog lets you adjust the contour sample resolution. See its `archive/` for version history — v1–v3 only matched same-orientation copies, v4 was rotation/direction independent but had a crashing bug, v4.1 fixed the crash, v4.2 added the options dialog. |

## Installing a gadget

1. Copy the gadget's whole `PGC_*` folder (the `.lua` file and, if present,
   its matching `.htm` file) into your VCarve gadgets folder — typically
   `C:\ProgramData\Vectric\VCarve Pro\V10.5\Gadgets`. (From VCarve's file
   menu: Open Application Data Folder.)
2. Restart VCarve Pro to load new Gadgets.
3. The gadget appears under the Gadgets panel/toolbar.

## Versioning convention

- Bump the `-- Version = X.Y` header comment in the script whenever behavior changes.
- When a script is replaced by a new working version, move the old file into
  that gadget's `archive/` subfolder rather than deleting it, and add a short
  note in the new version's header comment about what changed.
- Commit messages should say what changed and why, since the archive folder
  plus git history together are the full record.
