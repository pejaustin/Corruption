# Balance CSV Round-Trip

Iterate balance numbers in a spreadsheet. `scripts/build/balance_csv.gd`
(an `EditorScript`) round-trips every custom-`Resource` `.tres` under
`data/{minions,factions,abilities,upgrades,rituals}/` through CSVs in
`data/csv/`.

## Workflow

1. Open `scripts/build/balance_csv.gd` in the script editor.
2. Set `MODE` at the top to `"export"` or `"import"`.
3. **File → Run** (Cmd/Ctrl+Shift+X).

Export reads each target dir and writes one CSV per class
(`minions.csv`, `factions.csv`, …). Import reads each CSV and saves the
referenced `.tres` via `ResourceSaver.save()` (UIDs and `ext_resource`
links preserved — no hand-rolled `.tres` text).

## Encoding

| Type | CSV form |
|---|---|
| `int`, `float`, `bool`, `String`, `StringName` | literal |
| Enum (`MinionType.faction`, `UpgradeData.kind`, `RitualData.effect`, `FactionProfile.id`) | member name (`UNDEATH`, `MINION_HP`, …); ints also accepted |
| `Color` | `r,g,b,a` floats (CSV-quoted because of the commas) |
| `Vector2` / `Vector3` | comma-separated floats |
| `Resource` ref (`effect_scene`, `icon`, `default_avatar_scene`) | `res://...` path; empty = null |
| `Array[Resource]` (`avatar_abilities`) | `\|`-separated `res://` paths |

Headers come from the script's exported properties via
`get_property_list()`, so adding a new `@export` to a resource class
just shows up as a new column on the next export.

## Adding a new entry via CSV

Add a row whose `path` cell is the desired `res://data/<dir>/<id>.tres`.
On import, if the path doesn't exist the script instantiates a fresh
resource from the target's script (`scripts/<class>.gd`), creates parent
dirs, applies the row, and saves. Watch the editor log — new entries
print `created res://...` and the per-file summary includes a `(N new)`
count.

After import, refresh the FileSystem dock (or *Project → Reload
Current Project*) so the editor picks up new files.

## Skipped

- `MinionCatalog` (`data/minion_catalog.tres`) — single-row scene
  registry, manage in editor.
- `AttackData` (`data/attacks/*.tres`, Tier D) — not yet wired into
  `TARGETS`. The resource shape is CSV-friendly (no nested resources,
  all primitives + StringNames + one enum-like StringName for damage
  type) so adding an entry to `balance_csv.gd:TARGETS` is a one-liner:
  ```gdscript
  {"name": "attacks", "dir": "res://data/attacks/", "script": "res://scripts/combat/attack_data.gd"},
  ```
  Hold off until designers actually want to spreadsheet-tune
  per-attack frame data; until then editing the .tres files in the
  inspector is fine for the 8 starter attacks.
- Anything outside the five target dirs — add to `TARGETS` if you want
  a new resource class round-tripped.

## Caveats

- `Texture2D` references serialize as paths but have no balance value
  worth tweaking in CSV — easiest to leave the column blank to keep the
  current value, or set it in the editor.
- The script doesn't dry-run. Diff `git status` after import to verify
  what changed; revert if surprising.
- Rows whose `path` references a missing resource ref (e.g. typo in an
  `effect_scene` path) keep the existing value and emit a warning
  rather than nulling the field.
