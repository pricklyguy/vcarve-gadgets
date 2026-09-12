# VCarve Pro Gadgets

Custom Lua gadgets for VCarve Pro (developed against V10.516) — Prickly Guy Creations.

Each gadget lives in its own folder. The `.lua` file directly in a gadget's
folder is the current, working version — copy that one into your VCarve
Gadgets folder to use it. Anything superseded moves into that gadget's
`archive/` folder instead of being deleted, so there's always a record of
what changed and why.

## Gadgets

| Gadget | What it does |
|---|---|
| [`rotate-each-object-90`](rotate-each-object-90/) | Rotates every selected object 90° around its own center. |
| [`replace-circles-with-group`](replace-circles-with-group/) | Replaces selected circles with copies of a grouped template object, centered on each original circle. |
| [`count-selected-object`](count-selected-object/) | Counts selected vectors matching the last-selected object, rotation/translation/direction independent, and flags duplicates at the same location. See its archive for the version history — v1–v3 only matched same-orientation copies, v4 was rotation/direction independent but had a crashing bug, v4.1 is the current fixed version. |

## Installing a gadget

1. Copy the gadget's `.lua` file into your VCarve gadgets folder — typically
   `Documents\Vectric Files\Gadgets\VCarve Pro V10\` (per-user) or the shared
   `Gadgets` folder under the VCarve program data location.
2. Restart VCarve Pro, or use **File → Reload Gadgets** if your version has it.
3. The gadget appears under the Gadgets panel/toolbar.

## Versioning convention

- Bump the `-- Version = X.Y` header comment in the script whenever behavior changes.
- When a script is replaced by a new working version, move the old file into
  that gadget's `archive/` subfolder rather than deleting it, and add a short
  note in the new version's header comment about what changed.
- Commit messages should say what changed and why, since the archive folder
  plus git history together are the full record.
