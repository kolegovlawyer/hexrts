class_name UnitPreset
extends Resource

@export var preset_id: String = ""
@export var preset_name: String = "Боец"
@export var is_command: bool = false
@export var health: int = UnitPresetBalance.DEFAULT_STAT
@export var speed: int = UnitPresetBalance.DEFAULT_STAT
@export var damage: int = UnitPresetBalance.DEFAULT_STAT
@export var shield: int = UnitPresetBalance.DEFAULT_STAT
@export var range_stat: int = UnitPresetBalance.DEFAULT_STAT


static func create_default() -> UnitPreset:
	var preset := UnitPreset.new()
	preset.preset_id = "standard_fighter"
	preset.preset_name = UnitPresetBalance.default_preset_name()
	preset.is_command = false
	preset.apply_stats_dict(UnitPresetBalance.default_stats())
	return preset


static func create_fighter_default() -> UnitPreset:
	return create_default()


static func create_command_default() -> UnitPreset:
	var preset := UnitPreset.new()
	preset.preset_id = "standard_command"
	preset.preset_name = "КШМ"
	preset.is_command = true
	preset.apply_stats_dict(UnitPresetBalance.default_stats())
	return preset


static func create_artillery_default() -> UnitPreset:
	var preset := UnitPreset.new()
	preset.preset_id = "bot_artillery"
	preset.preset_name = "Артиллерия"
	preset.is_command = false
	preset.apply_stats_dict({
		"health": 5,
		"speed": 5,
		"damage": 5,
		"shield": 5,
		"range": 20,
	})
	return preset


func duplicate_preset() -> UnitPreset:
	var copy: UnitPreset = duplicate(true)
	copy.preset_id = ""
	return copy


func apply_stats_dict(stats: Dictionary) -> void:
	health = UnitPresetBalance.clamp_stat(int(stats.get("health", UnitPresetBalance.DEFAULT_STAT)))
	speed = UnitPresetBalance.clamp_stat(int(stats.get("speed", UnitPresetBalance.DEFAULT_STAT)))
	damage = UnitPresetBalance.clamp_stat(int(stats.get("damage", UnitPresetBalance.DEFAULT_STAT)))
	shield = UnitPresetBalance.clamp_stat(int(stats.get("shield", UnitPresetBalance.DEFAULT_STAT)))
	range_stat = UnitPresetBalance.clamp_stat(int(stats.get("range", UnitPresetBalance.DEFAULT_STAT)))


func get_stats_dict() -> Dictionary:
	return {
		"health": health,
		"speed": speed,
		"damage": damage,
		"shield": shield,
		"range": range_stat,
	}


func get_cost() -> int:
	return UnitPresetBalance.calculate_cost(get_stats_dict(), is_command)


func get_spawn_time() -> float:
	return UnitPresetBalance.calculate_spawn_time(get_cost())


func get_unit_type() -> String:
	return "command_unit" if is_command else "base_unit"


func to_spawn_snapshot() -> Dictionary:
	var stats := get_stats_dict()
	stats["is_command"] = is_command
	stats["preset_id"] = preset_id
	stats["preset_name"] = preset_name
	return stats


func to_dict() -> Dictionary:
	return {
		"preset_id": preset_id,
		"preset_name": preset_name,
		"is_command": is_command,
		"health": health,
		"speed": speed,
		"damage": damage,
		"shield": shield,
		"range": range_stat,
	}


static func from_dict(data: Dictionary) -> UnitPreset:
	if data.is_empty():
		return null

	var stats := {
		"health": data.get("health", UnitPresetBalance.DEFAULT_STAT),
		"speed": data.get("speed", UnitPresetBalance.DEFAULT_STAT),
		"damage": data.get("damage", UnitPresetBalance.DEFAULT_STAT),
		"shield": data.get("shield", UnitPresetBalance.DEFAULT_STAT),
		"range": data.get("range", UnitPresetBalance.DEFAULT_STAT),
	}
	var is_command_flag := bool(data.get("is_command", false))
	if not UnitPresetBalance.is_valid_preset_stats(stats, is_command_flag):
		return null

	var preset := UnitPreset.new()
	preset.preset_id = str(data.get("preset_id", ""))
	preset.preset_name = str(data.get("preset_name", UnitPresetBalance.default_preset_name()))
	preset.is_command = is_command_flag
	preset.apply_stats_dict(stats)
	return preset
