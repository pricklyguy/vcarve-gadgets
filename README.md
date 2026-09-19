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
| [`PGC_Replace_Circles`](PGC_Replace_Circles/) | `PGC_Replace_Circles.lua` — Replaces selected circles with copies of a grouped template object, centered on each original circle. A dialog lets you choose whether to keep the original template after replacement, and whether to back up replaced circles for undo (see below). |
| [`PGC_Count_Selected_Objects`](PGC_Count_Selected_Objects/) | `PGC_Count_Selected_Objects.lua` — Counts selected vectors matching the last-selected object, rotation/translation/direction independent, and flags duplicates at the same location. A dialog lets you adjust the contour sample resolution. Doesn't modify the drawing, so it has no undo concerns. See its `archive/` for version history — v1–v3 only matched same-orientation copies, v4 was rotation/direction independent but had a crashing bug, v4.1 fixed the crash, v4.2 added the options dialog. |
| [`PGC_Nudge_To_Guide`](PGC_Nudge_To_Guide/) | `PGC_Nudge_To_Guide.lua` — For cleaning up hand-drawn layouts (e.g. LED holes along a spider leg): select the circles/notches to align, then Shift-select a guide line/arc/polyline LAST, and it nudges each one onto the closest point of the guide. A dialog option evenly redistributes them along the guide afterward, between the first and last object's position. |
| [`PGC_Marker_Offset`](PGC_Marker_Offset/) | `PGC_Marker_Offset.lua` — For drawing a wiring guide onto a prop with a marker/pen mounted beside the spindle. Copies the selected vectors onto a `PGC Marker Path` layer, shifted by the opposite of the marker's offset from the spindle (entered in the dialog; defaults to X 0, Y −58 mm, remembered between runs, shown in the job's own units). Make the marker toolpath from the copies using the same work zero as the cutting job — a Drag Knife toolpath with blade offset 0 works well, since VCarve won't accept a zero-speed dummy tool. Pairs with `tools/xmodel_wiring_export`, which generates the wiring paths. |
| [`PGC_Undo_Last`](PGC_Undo_Last/) | `PGC_Undo_Last.lua` — Reverses the most recent change made by any of the gadgets above, since VCarve's own Ctrl+Z does not see changes gadgets make. See "Undo support" below. |

## Undo support

VCarve's built-in Undo does not see changes made by gadgets, so a bad result
used to mean closing the file without saving and starting over. `PGC_Rotate`,
`PGC_Nudge_To_Guide`, and `PGC_Replace_Circles` now write a small log
(`PGC_Undo_Log.txt`, kept alongside the gadget folders — not committed to this
repo) describing how to reverse what they just did. Run `PGC_Undo_Last`
afterward, same as you would Ctrl+Z, and it reverses the most recent entry;
run it again to step back through up to the last 10 PGC changes.

`PGC_Replace_Circles` also has its own "Back up replaced circles" option
(on by default): instead of deleting a replaced circle outright, it leaves a
copy on a `PGC Undo Backup` layer. When that option was on, `PGC_Undo_Last`
moves the backup back onto the replacement's original layer and deletes the
replacement, so the circle actually reappears. With the option off, there's
nothing to restore — the original geometry is gone for good, so undo just
removes the replacement (same as if you'd selected and deleted it). Any
backups left over after you're happy with a result can be cleared out by
hand; they aren't removed automatically.

## Tools (not gadgets)

| Tool | What it does |
|---|---|
| [`tools/xmodel_wiring_export`](tools/xmodel_wiring_export/) | `PGC_Wiring_Export.ps1` — standalone PowerShell script (runs outside VCarve). Converts an xLights `.xmodel` export into a DXF: one polyline per LED string in true wiring order (for a spindle-mounted marker to trace), plus one reference circle per node at its exact position (feed these into `PGC_Replace_Circles` for accurate hole placement). See its own README for usage. |

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
