class_name ArenaConfig extends Resource

## One fight in the combat test arena (tools/arena/arena.tscn): who you play, how,
## and what you face. Save presets as .tres beside this script; the arena's
## `config` export, `--arena-preset=<path>` or the setup panel picks one.

enum Role { PALADIN, BOSS }
enum Opponent {
	AI,      ## Paladin: a CPU boss. Boss: the AI-driven Paladin (the good faction's).
	PLAYER,  ## The second player, in the other role (they join over the network).
	MINIONS, ## `minion_count` of `minion_type`, hostile to you.
	NONE,    ## Nobody: walk around, try the moves.
}

@export var role: Role = Role.PALADIN
## The Paladin's control level (1 walk .. 4 everything; AvatarActor.CONTROL_UNLOCKS).
@export_range(1, 4) var control_level: int = 4
## The boss form's attacks, in key order (each BossAttack names its own key).
@export var boss_attacks: Array[BossAttack] = []
@export var boss_hp: int = 300
@export var boss_damage: int = 20
@export var opponent: Opponent = Opponent.AI
## A MinionType id from data/minion_catalog.tres (MINIONS).
@export var minion_type: StringName = &"skeleton"
@export_range(1, 20) var minion_count: int = 1

func other_role() -> Role:
	return Role.BOSS if role == Role.PALADIN else Role.PALADIN

func to_dict() -> Dictionary:
	## For the round RPC: plain values only.
	var attack_paths: Array[String] = []
	for attack in boss_attacks:
		attack_paths.push_back(attack.resource_path)
	return {
		"role": role, "control_level": control_level, "boss_attacks": attack_paths,
		"boss_hp": boss_hp, "boss_damage": boss_damage, "opponent": opponent,
		"minion_type": String(minion_type), "minion_count": minion_count,
	}

static func from_dict(d: Dictionary) -> ArenaConfig:
	var c := ArenaConfig.new()
	c.role = d.get("role", Role.PALADIN)
	c.control_level = d.get("control_level", 4)
	for path: String in d.get("boss_attacks", []):
		var attack := load(path) as BossAttack
		if attack:
			c.boss_attacks.push_back(attack)
	c.boss_hp = d.get("boss_hp", 300)
	c.boss_damage = d.get("boss_damage", 20)
	c.opponent = d.get("opponent", Opponent.AI)
	c.minion_type = StringName(d.get("minion_type", "skeleton"))
	c.minion_count = d.get("minion_count", 1)
	return c

func apply_args(args: PackedStringArray) -> void:
	## Command-line overrides (after `--`): --role=paladin|boss --level=N
	## --opponent=ai|player|minions|none --minion=<id> --count=N --boss-hp=N
	## --boss-damage=N --attacks=<name>,<name> (file names in data/bosses/, any depth).
	for arg in args:
		var parts := arg.trim_prefix("--").split("=", true, 1)
		var key := parts[0]
		var value := parts[1] if parts.size() > 1 else ""
		match key:
			"role": role = Role.BOSS if value == "boss" else Role.PALADIN
			"level": control_level = clampi(value.to_int(), 1, 4)
			"opponent": opponent = {"ai": Opponent.AI, "player": Opponent.PLAYER, "minions": Opponent.MINIONS, "none": Opponent.NONE}.get(value, opponent)
			"minion": minion_type = StringName(value)
			"count": minion_count = clampi(value.to_int(), 1, 20)
			"boss-hp": boss_hp = value.to_int()
			"boss-damage": boss_damage = value.to_int()
			"attacks":
				boss_attacks.clear()
				var all := ArenaConfig.all_boss_attacks()
				for name in value.split(",", false):
					for attack in all:
						if attack.resource_path.get_file().get_basename() == name:
							boss_attacks.push_back(attack)

static func all_boss_attacks() -> Array[BossAttack]:
	## Every BossAttack under res://data/bosses/, sorted by path.
	var found: Array[BossAttack] = []
	_collect_attacks("res://data/bosses", found)
	found.sort_custom(func(a: BossAttack, b: BossAttack) -> bool: return a.resource_path < b.resource_path)
	return found

static func _collect_attacks(dir_path: String, found: Array[BossAttack]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect_attacks(dir_path.path_join(sub), found)
	for file in dir.get_files():
		var path := dir_path.path_join(file.trim_suffix(".remap"))
		if path.ends_with(".tres"):
			var attack := load(path) as BossAttack
			if attack:
				found.push_back(attack)
