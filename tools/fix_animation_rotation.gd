@tool
extends EditorScript

## Run this from the Godot editor: File → Run Script
## Fixes animations in the large-male AnimationLibrary that have a 90-degree
## X-axis rotation baked into the root bone. Compares each animation's root
## bone rotation against the known-good Idle animation and corrects the offset.

const LIBRARY_PATH := "res://scenes/avatar/large-male.res"

# Animations that are already correct — skip these
const SKIP := [
	"Attack",
	"Idle",
	"Punch",
	"TPose",
	"T-Pose",
	"Tting Pose",
]

func _run():
	var lib: AnimationLibrary = load(LIBRARY_PATH)
	if not lib:
		print("ERROR: Could not load ", LIBRARY_PATH)
		return

	var anim_list := lib.get_animation_list()
	print("Found %d animations in library" % anim_list.size())

	# The fix: a -90 degree X rotation means the skeleton was exported Z-up.
	# We need to undo that by composing with a +90 X correction quaternion.
	# Quaternion for +90 degrees around X axis:
	var correction := Quaternion(Vector3(1, 0, 0), deg_to_rad(90))

	var fixed_count := 0
	for anim_name in anim_list:
		# Skip known-good animations
		var skip := false
		for s in SKIP:
			if anim_name.to_lower() == s.to_lower():
				skip = true
				break
		if skip:
			print("  SKIP: %s (known good)" % anim_name)
			continue

		var anim: Animation = lib.get_animation(anim_name)
		if not anim:
			continue

		var found_root := false
		for track_idx in anim.get_track_count():
			var path := anim.track_get_path(track_idx)
			if anim.track_get_type(track_idx) != Animation.TYPE_ROTATION_3D:
				continue
			# The root bone track's subpath (after ':') should be the bone name.
			# Check for common root bone names via the subpath only,
			# not the full path (which contains "Root/" as a node name).
			var subpath := path.get_concatenated_subnames()
			if subpath != "Hips" and subpath != "Root" and subpath != "root" and subpath != "Armature":
				continue

			found_root = true
			# Apply correction to every keyframe on this track
			for key_idx in anim.track_get_key_count(track_idx):
				var rot: Quaternion = anim.track_get_key_value(track_idx, key_idx)
				anim.track_set_key_value(track_idx, key_idx, correction * rot)

			print("  FIXED: %s (%d rotation keys corrected)" % [anim_name, anim.track_get_key_count(track_idx)])
			fixed_count += 1
			break

		if not found_root:
			print("  WARN: %s — no root bone rotation track found" % anim_name)

	# Save the modified library
	if fixed_count > 0:
		var err := ResourceSaver.save(lib, LIBRARY_PATH)
		if err == OK:
			print("\nSaved %d fixed animations to %s" % [fixed_count, LIBRARY_PATH])
		else:
			print("\nERROR saving: %d" % err)
	else:
		print("\nNo animations needed fixing.")
