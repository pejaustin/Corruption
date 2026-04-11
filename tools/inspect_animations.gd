@tool
extends EditorScript

## Run from Godot editor: File → Run Script
## Compares the first keyframe of every track between a known-good animation
## and a broken one to identify what's different.

const LIBRARY_PATH := "res://scenes/avatar/large-male.res"
const GOOD_ANIM := "Idle"   # Known to be correct
const BAD_ANIM := "Run"     # Known to be rotated 90 degrees

func _run():
	var lib: AnimationLibrary = load(LIBRARY_PATH)
	if not lib:
		print("ERROR: Could not load ", LIBRARY_PATH)
		return

	var good: Animation = lib.get_animation(GOOD_ANIM)
	var bad: Animation = lib.get_animation(BAD_ANIM)

	if not good:
		print("ERROR: Animation '%s' not found. Available: %s" % [GOOD_ANIM, str(lib.get_animation_list())])
		return
	if not bad:
		print("ERROR: Animation '%s' not found. Available: %s" % [BAD_ANIM, str(lib.get_animation_list())])
		return

	print("=== GOOD animation: %s (%d tracks) ===" % [GOOD_ANIM, good.get_track_count()])
	print("=== BAD animation:  %s (%d tracks) ===" % [BAD_ANIM, bad.get_track_count()])
	print("")

	# Build a lookup of good animation tracks by path+type
	var good_tracks := {}  # "path|type" -> {type, value}
	for i in good.get_track_count():
		var path := str(good.track_get_path(i))
		var type := good.track_get_type(i)
		var key := "%s|%d" % [path, type]
		var value = null
		if good.track_get_key_count(i) > 0:
			value = good.track_get_key_value(i, 0)
		good_tracks[key] = {"path": path, "type": type, "value": value}

	# Now compare bad animation tracks
	print("--- Tracks with DIFFERENT first-frame values ---")
	print("")
	var diff_count := 0
	for i in bad.get_track_count():
		var path := str(bad.track_get_path(i))
		var type := bad.track_get_type(i)
		var key := "%s|%d" % [path, type]
		var bad_value = null
		if bad.track_get_key_count(i) > 0:
			bad_value = bad.track_get_key_value(i, 0)

		if key in good_tracks:
			var good_value = good_tracks[key]["value"]
			if not _values_close(good_value, bad_value, type):
				var type_name := _type_name(type)
				print("  DIFF [%s] %s" % [type_name, path])
				print("    good: %s" % _format_value(good_value, type))
				print("     bad: %s" % _format_value(bad_value, type))
				if type == Animation.TYPE_ROTATION_3D and good_value is Quaternion and bad_value is Quaternion:
					var good_euler: Vector3 = good_value.get_euler() * (180.0 / PI)
					var bad_euler: Vector3 = bad_value.get_euler() * (180.0 / PI)
					print("    good euler: (%.1f, %.1f, %.1f)" % [good_euler.x, good_euler.y, good_euler.z])
					print("     bad euler: (%.1f, %.1f, %.1f)" % [bad_euler.x, bad_euler.y, bad_euler.z])
					var diff_euler := bad_euler - good_euler
					print("    diff euler: (%.1f, %.1f, %.1f)" % [diff_euler.x, diff_euler.y, diff_euler.z])
				print("")
				diff_count += 1
		else:
			print("  EXTRA track in bad (not in good): [%s] %s = %s" % [_type_name(type), path, bad_value])
			diff_count += 1

	# Check for tracks in good but missing from bad
	for i in good.get_track_count():
		var path := str(good.track_get_path(i))
		var type := good.track_get_type(i)
		var key := "%s|%d" % [path, type]
		var found := false
		for j in bad.get_track_count():
			var bkey := "%s|%d" % [str(bad.track_get_path(j)), bad.track_get_type(j)]
			if bkey == key:
				found = true
				break
		if not found:
			print("  MISSING from bad (present in good): [%s] %s" % [_type_name(type), path])

	print("--- Total differences: %d ---" % diff_count)

func _values_close(a, b, type: int) -> bool:
	if a == null or b == null:
		return a == b
	match type:
		Animation.TYPE_ROTATION_3D:
			if a is Quaternion and b is Quaternion:
				return a.dot(b) > 0.999
		Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D:
			if a is Vector3 and b is Vector3:
				return a.distance_to(b) < 0.01
	return a == b

func _type_name(type: int) -> String:
	match type:
		Animation.TYPE_POSITION_3D: return "POS"
		Animation.TYPE_ROTATION_3D: return "ROT"
		Animation.TYPE_SCALE_3D: return "SCL"
		_: return "T%d" % type

func _format_value(val, type: int) -> String:
	if val is Quaternion:
		return "Quat(%.4f, %.4f, %.4f, %.4f)" % [val.x, val.y, val.z, val.w]
	if val is Vector3:
		return "Vec3(%.4f, %.4f, %.4f)" % [val.x, val.y, val.z]
	return str(val)
