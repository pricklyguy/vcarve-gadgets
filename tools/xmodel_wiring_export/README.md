# PGC_Wiring_Export

A standalone PowerShell script (not a VCarve gadget - it runs on its own,
outside VCarve) that converts an xLights `.xmodel` export into a DXF you can
import into VCarve.

## What it's for

When a pixel prop (spider legs, a web, an arch, etc.) is drilled/cut by hand
in VCarve, the hole positions don't always line up exactly with the true
node positions from the xLights model - especially on complex layouts. This
script reads the exact node data straight out of the xLights model export
and produces:

- **`STRING_1`, `STRING_2`, ...** (one layer per physical LED string) - a
  single polyline per string, connecting its nodes in true wiring order.
  Trace this with a marker mounted on the spindle (offset from the cutting
  tool) to draw a wiring guide directly onto the prop before cutting. Where
  a straight line between two consecutive nodes would pass through an
  unrelated pixel's hole - ambiguous, since it then looks like the wire
  terminates there - the path automatically kinks around it instead.
- **`NODE_POINTS`** - one small circle at every node's exact position.
  Select these along with your circle+notch template (selected last) and
  run `PGC_Replace_Circles` (see the main gadgets in this repo) to place
  accurately-positioned pixel holes, instead of hand-drawn ones that may be
  slightly off.

All output is in real-world millimeters, at true 1:1 scale with the
physical prop (taken from the model's actual `widthmm`/`heightmm`, not its
internal display scale).

## Getting the .xmodel file

In xLights: **Layout** tab, right-click the model, **Export model as...**
This exports a single model's definition, not the whole show.

Only "Custom Model" types (built from a node grid, like `Web L` above) carry
the per-node `CustomModelCompressed` position table this script needs.
Simpler built-in model shapes (arches, matrices defined purely by
width/height/strand counts) don't necessarily export explicit per-node
positions the same way.

## Desktop app (no command line)

`PGC_Wiring_Export_GUI.ps1` is a small Windows Forms front-end for the same
script - file pickers and option boxes instead of typing a command line.
It shells out to `PGC_Wiring_Export.ps1` (which must stay in the same
folder), so that script remains the single source of truth for the actual
conversion logic.

**One-time setup:** run `Install-Desktop-Shortcut.ps1` (double-click, or
right-click > Run with PowerShell) to create a **"PGC Wiring Export"**
shortcut on your Desktop. After that, just double-click the shortcut -
no console window, just the app.

Known cosmetic issue: the first "Browse..." button sometimes renders in
the wrong spot on open (confirmed NOT a display-scaling issue - reproduces
at 100% scale). Everything still works correctly (file picking, all
options, DXF generation) despite the visual glitch. Not yet root-caused -
couldn't be reproduced/debugged further since this was built in an
environment with no interactive desktop to render/screenshot a live
WinForms window against.

## Running it from the command line

```powershell
powershell -ExecutionPolicy Bypass -File .\PGC_Wiring_Export.ps1 "C:\path\to\Model Name.xmodel"
```

This writes a `.dxf` next to the input file by default. Optional
parameters:

```powershell
.\PGC_Wiring_Export.ps1 -InputPath "Web L.xmodel" -OutputPath "Z:\Halloween\Web_L.dxf" -PointRadius 2.0 -HoleDiameter 10
```

- `-OutputPath` - where to write the DXF (default: same folder/name as the input, with a `.dxf` extension).
- `-PointRadius` - radius in mm of the `NODE_POINTS` circles (default 1.5mm). Cosmetic only - `PGC_Replace_Circles` only uses each circle's center.
- `-HoleDiameter` - diameter in mm of the actual drilled pixel hole, used as the keep-out zone for routing wiring-path segments around pixels they don't connect to. If not given, the script tries to read it from the model's `PixelType` attribute (e.g. `"12mm bullet or square"` -> 12mm); falls back to 15mm if that can't be parsed (e.g. `PixelType` is just `"Bullets"` with no size). The fallback was bumped from an earlier 12mm default after real notches/holes turned out to run a bit bigger than that. Pass this explicitly if your model's `PixelType` doesn't include a clean `Nmm` size and your actual holes aren't ~15mm.
- `-ClearanceMargin` - extra clearance in mm added outside the hole radius when routing around an obstacle (default 1.0mm), so the path doesn't just graze the edge of the hole.
- `-OrientToVCarve true|false` - every model exported so far has needed a manual 270-degree rotate + horizontal flip in VCarve to line up with the actual drawing. On (`true`) by default, this bakes that same transform into the output so the manual step is no longer needed. Pass `false` for the raw, un-rotated xLights layout instead. Takes the word `true`/`false` (not `$true`/`$false`) - a script invoked with `-File` only ever receives plain text on the command line, and PowerShell's `[bool]` parameter binding rejects that text outright even though its own error message suggests otherwise; this parameter is deliberately typed as a string and parsed by hand to work around that.

The script prints how many detours it added, e.g.
`Hole keep-out: 12mm diameter + 1mm clearance -> routed around 6 pixel(s) the path would otherwise have crossed`.

The `-ExecutionPolicy Bypass` is only needed if Windows blocks running
unsigned local scripts by default on your machine; it doesn't change any
system-wide setting.

## Importing into VCarve

File > Import > Import Vectors > pick the `.dxf` > choose **Millimeters**
as the unit. It comes in as separate layers (one per string, plus
`NODE_POINTS`) which you can move/scale/mirror with VCarve's native tools
to align against your actual drawing - it's at true 1:1 scale, so normally
only a position nudge (and possibly a mirror, for back-side "reverse view"
cutting) should be needed.
