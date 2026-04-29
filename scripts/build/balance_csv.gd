@tool
extends EditorScript

## Round-trips custom-Resource .tres files (MinionType, FactionProfile,
## AvatarAbility, UpgradeData, RitualData) through CSVs under res://data/csv/
## so balance values can be edited in a spreadsheet.
##
## Usage:
##   1. Set MODE below to "export" or "import".
##   2. Open this file in the Godot script editor.
##   3. File → Run (Ctrl+Shift+X on Linux/Win, Cmd+Shift+X on Mac).
##
## Export: reads every .tres in each TARGETS dir and writes one CSV per class.
## Import: reads each CSV, loads the .tres referenced by the `path` column,
##         applies values via res.set(), saves with ResourceSaver.save().
##         If `path` does not exist on disk, a new resource is instantiated
##         from the target's script and saved at that path (parent dirs
##         created as needed).
##
## Enums serialize as their member names (e.g. `MINION_HP`, `UNDEATH`)
## rather than ints. Integer values are still accepted on import.
##
## Skipped: MinionCatalog (single-row scene registry — manage in editor).

const MODE: String = "export"

const CSV_DIR: String = "res://data/csv/"

const TARGETS: Array[Dictionary] = [
	{"name": "minions",   "dir": "res://data/minions/",   "script": "res://scripts/minion_type.gd"},
	{"name": "factions",  "dir": "res://data/factions/",  "script": "res://scripts/faction_profile.gd"},
	{"name": "abilities", "dir": "res://data/abilities/", "script": "res://scripts/avatar_ability.gd"},
	{"name": "upgrades",  "dir": "res://data/upgrades/",  "script": "res://scripts/upgrade_data.gd"},
	{"name": "rituals",   "dir": "res://data/rituals/",   "script": "res://scripts/ritual_data.gd"},
]

const _SKIP_PROPS: Array[String] = [
	"script",
	"resource_local_to_scene",
	"resource_path",
	"resource_name",
	"resource_scene_unique_id",
]

const _ARRAY_SEP: String = "|"


func _run() -> void:
	if not DirAccess.dir_exists_absolute(CSV_DIR):
		DirAccess.make_dir_recursive_absolute(CSV_DIR)
	match MODE:
		"export":
			for target in TARGETS:
				_export_target(target)
		"import":
			for target in TARGETS:
				_import_target(target)
		_:
			push_error("[balance_csv] unknown MODE %s — use 'export' or 'import'" % MODE)
			return
	print("[balance_csv] %s complete" % MODE)


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

func _export_target(target: Dictionary) -> void:
	var dir: String = target["dir"]
	var paths: Array[String] = _collect_tres(dir)

	# Header columns come from the script's own property list, so an empty
	# directory still produces a usable CSV with the right schema.
	var template: Resource = _instantiate_from(target)
	if template == null:
		return
	var props: Array = _exportable_properties(template)
	var headers: Array = ["path"]
	for prop in props:
		headers.append(prop["name"])

	var rows: Array = [headers]
	for p in paths:
		var res: Resource = load(p) as Resource
		if res == null:
			push_warning("[balance_csv] failed to load %s" % p)
			continue
		var row: Array = [p]
		for prop in props:
			row.append(_serialize(res.get(prop["name"]), prop))
		rows.append(row)

	var csv_path: String = CSV_DIR + (target["name"] as String) + ".csv"
	_write_csv(csv_path, rows)
	print("  wrote %s (%d rows)" % [csv_path, rows.size() - 1])


# ---------------------------------------------------------------------------
# Import
# ---------------------------------------------------------------------------

func _import_target(target: Dictionary) -> void:
	var csv_path: String = CSV_DIR + (target["name"] as String) + ".csv"
	if not FileAccess.file_exists(csv_path):
		push_warning("[balance_csv] missing %s, skipping" % csv_path)
		return

	var rows: Array = _read_csv(csv_path)
	if rows.size() < 2:
		return

	var headers: Array = rows[0]
	var path_col: int = headers.find("path")
	if path_col < 0:
		push_error("[balance_csv] %s has no 'path' column" % csv_path)
		return

	var saved: int = 0
	var created: int = 0
	for i in range(1, rows.size()):
		var row: Array = rows[i]
		if row.size() == 0 or (row.size() == 1 and row[0] == ""):
			continue
		while row.size() < headers.size():
			row.append("")
		var res_path: String = row[path_col]
		if res_path == "":
			continue

		var res: Resource
		var is_new: bool = not ResourceLoader.exists(res_path)
		if is_new:
			res = _instantiate_from(target)
			if res == null:
				push_error("[balance_csv] cannot create %s — instantiation failed" % res_path)
				continue
			var dir_path: String = res_path.get_base_dir()
			if dir_path != "" and not DirAccess.dir_exists_absolute(dir_path):
				DirAccess.make_dir_recursive_absolute(dir_path)
		else:
			res = load(res_path) as Resource
			if res == null:
				push_warning("[balance_csv] could not load %s" % res_path)
				continue

		var props: Array = _exportable_properties(res)
		var by_name: Dictionary = {}
		for prop in props:
			by_name[prop["name"]] = prop

		for col in range(headers.size()):
			if col == path_col:
				continue
			var prop_name: String = headers[col]
			if not by_name.has(prop_name):
				continue
			var current = res.get(prop_name)
			var new_val = _deserialize(row[col], by_name[prop_name], current)
			res.set(prop_name, new_val)

		var err: int = ResourceSaver.save(res, res_path)
		if err != OK:
			push_error("[balance_csv] save failed for %s (err=%d)" % [res_path, err])
		else:
			saved += 1
			if is_new:
				created += 1
				print("  created %s" % res_path)
	print("  imported %s → saved %d resources (%d new)" % [csv_path, saved, created])


func _instantiate_from(target: Dictionary) -> Resource:
	var script_path: String = target.get("script", "")
	if script_path == "":
		push_error("[balance_csv] target %s has no script" % target.get("name", "?"))
		return null
	var script: Script = load(script_path) as Script
	if script == null:
		push_error("[balance_csv] could not load script %s" % script_path)
		return null
	var res: Resource = script.new() as Resource
	if res == null:
		push_error("[balance_csv] %s did not instantiate as Resource" % script_path)
	return res


# ---------------------------------------------------------------------------
# Property introspection
# ---------------------------------------------------------------------------

func _exportable_properties(res: Resource) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for prop in res.get_property_list():
		var pname: String = prop["name"]
		if seen.has(pname):
			continue
		seen[pname] = true
		if pname in _SKIP_PROPS:
			continue
		var usage: int = prop["usage"]
		if usage & PROPERTY_USAGE_GROUP or usage & PROPERTY_USAGE_SUBGROUP or usage & PROPERTY_USAGE_CATEGORY:
			continue
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if not (usage & PROPERTY_USAGE_STORAGE):
			continue
		out.append(prop)
	return out


# ---------------------------------------------------------------------------
# Serialize / Deserialize
# ---------------------------------------------------------------------------

func _serialize(v: Variant, prop: Dictionary) -> String:
	if v == null:
		return ""
	if _is_enum(prop):
		return _enum_value_to_name(int(v), prop["hint_string"])
	match typeof(v):
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			return _trim_float(v)
		TYPE_STRING:
			return v
		TYPE_STRING_NAME:
			return String(v)
		TYPE_COLOR:
			var c: Color = v
			return "%s,%s,%s,%s" % [_trim_float(c.r), _trim_float(c.g), _trim_float(c.b), _trim_float(c.a)]
		TYPE_VECTOR2:
			var v2: Vector2 = v
			return "%s,%s" % [_trim_float(v2.x), _trim_float(v2.y)]
		TYPE_VECTOR3:
			var v3: Vector3 = v
			return "%s,%s,%s" % [_trim_float(v3.x), _trim_float(v3.y), _trim_float(v3.z)]
		TYPE_OBJECT:
			if v is Resource:
				return (v as Resource).resource_path
			return ""
		TYPE_ARRAY:
			var arr: Array = v
			var parts: Array = []
			for el in arr:
				if el is Resource:
					parts.append((el as Resource).resource_path)
				else:
					parts.append(str(el))
			return _ARRAY_SEP.join(parts)
	return str(v)


func _deserialize(text: String, prop: Dictionary, current: Variant) -> Variant:
	var t: int = prop["type"]

	if text == "":
		match t:
			TYPE_OBJECT:
				return null
			TYPE_ARRAY:
				if current is Array:
					(current as Array).clear()
					return current
				return []
			TYPE_STRING:
				return ""
			TYPE_STRING_NAME:
				return StringName("")

	if _is_enum(prop):
		return _enum_name_to_value(text, prop["hint_string"])

	match t:
		TYPE_BOOL:
			return text.to_lower() == "true"
		TYPE_INT:
			return int(text)
		TYPE_FLOAT:
			return float(text)
		TYPE_STRING:
			return text
		TYPE_STRING_NAME:
			return StringName(text)
		TYPE_COLOR:
			var parts: PackedStringArray = text.split(",")
			if parts.size() < 3:
				return current if current is Color else Color.WHITE
			var a: float = float(parts[3]) if parts.size() >= 4 else 1.0
			return Color(float(parts[0]), float(parts[1]), float(parts[2]), a)
		TYPE_VECTOR2:
			var p2: PackedStringArray = text.split(",")
			if p2.size() < 2:
				return Vector2.ZERO
			return Vector2(float(p2[0]), float(p2[1]))
		TYPE_VECTOR3:
			var p3: PackedStringArray = text.split(",")
			if p3.size() < 3:
				return Vector3.ZERO
			return Vector3(float(p3[0]), float(p3[1]), float(p3[2]))
		TYPE_OBJECT:
			if not ResourceLoader.exists(text):
				push_warning("[balance_csv] resource not found: %s" % text)
				return current
			return load(text)
		TYPE_ARRAY:
			# Reuse the existing typed Array so its element type is preserved
			# (Array[AvatarAbility], Array[PackedScene], etc.). Untyped fallback otherwise.
			var paths: PackedStringArray = text.split(_ARRAY_SEP, false)
			if current is Array:
				var arr: Array = current
				arr.clear()
				for p in paths:
					if p == "":
						continue
					if ResourceLoader.exists(p):
						arr.append(load(p))
					else:
						push_warning("[balance_csv] array element not found: %s" % p)
				return arr
			var fallback: Array = []
			for p in paths:
				if p != "" and ResourceLoader.exists(p):
					fallback.append(load(p))
			return fallback
	return text


func _is_enum(prop: Dictionary) -> bool:
	return prop.get("type", -1) == TYPE_INT and prop.get("hint", 0) == PROPERTY_HINT_ENUM


func _enum_value_to_name(value: int, hint_string: String) -> String:
	# hint_string is "NAME:0,NAME:1,..." (or just "NAME,NAME,..." for implicit indices).
	var pairs: PackedStringArray = hint_string.split(",")
	for idx in pairs.size():
		var pair: String = pairs[idx]
		var bits: PackedStringArray = pair.split(":")
		var entry_name: String = bits[0]
		var entry_value: int = int(bits[1]) if bits.size() == 2 else idx
		if entry_value == value:
			return entry_name
	return str(value)


func _enum_name_to_value(text: String, hint_string: String) -> int:
	var stripped: String = text.strip_edges()
	if stripped.is_valid_int():
		return int(stripped)
	var pairs: PackedStringArray = hint_string.split(",")
	for idx in pairs.size():
		var pair: String = pairs[idx]
		var bits: PackedStringArray = pair.split(":")
		var entry_name: String = bits[0]
		var entry_value: int = int(bits[1]) if bits.size() == 2 else idx
		if entry_name == stripped:
			return entry_value
	push_warning("[balance_csv] unknown enum value '%s' (allowed: %s)" % [text, hint_string])
	return 0


func _trim_float(f: float) -> String:
	# Keep CSVs readable: drop trailing zeros, but stay round-trip-safe.
	var s: String = String.num(f, 6)
	if "." in s:
		s = s.rstrip("0").rstrip(".")
		if s == "" or s == "-":
			s = "0"
	return s


# ---------------------------------------------------------------------------
# Filesystem
# ---------------------------------------------------------------------------

func _collect_tres(dir: String) -> Array[String]:
	var result: Array[String] = []
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		push_warning("[balance_csv] cannot open %s" % dir)
		return result
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".tres"):
			result.append(dir + f)
		f = d.get_next()
	result.sort()
	return result


# ---------------------------------------------------------------------------
# CSV
# ---------------------------------------------------------------------------

func _write_csv(path: String, rows: Array) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[balance_csv] cannot write %s" % path)
		return
	for row in rows:
		var cells: PackedStringArray = []
		for cell in row:
			cells.append(_csv_escape(str(cell)))
		f.store_line(",".join(cells))


func _csv_escape(s: String) -> String:
	if s.contains(",") or s.contains("\"") or s.contains("\n") or s.contains("\r"):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s


func _read_csv(path: String) -> Array:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var text: String = f.get_as_text()
	return _parse_csv(text)


func _parse_csv(text: String) -> Array:
	var rows: Array = []
	var row: Array = []
	var cell: String = ""
	var in_quotes: bool = false
	var i: int = 0
	var n: int = text.length()
	while i < n:
		var c: String = text[i]
		if in_quotes:
			if c == "\"":
				if i + 1 < n and text[i + 1] == "\"":
					cell += "\""
					i += 1
				else:
					in_quotes = false
			else:
				cell += c
		else:
			if c == "\"":
				in_quotes = true
			elif c == ",":
				row.append(cell)
				cell = ""
			elif c == "\n":
				row.append(cell)
				rows.append(row)
				row = []
				cell = ""
			elif c == "\r":
				pass
			else:
				cell += c
		i += 1
	if cell != "" or not row.is_empty():
		row.append(cell)
		rows.append(row)
	return rows
