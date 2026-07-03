class_name UnitPreset
extends Resource

@export var preset_id: String = ""
@export var preset_name: String = "МК-1"
@export var is_command: bool = false
@export var health: int = UnitPresetBalance.DEFAULT_STAT
@export var speed: int = UnitPresetBalance.DEFAULT_STAT
@export var damage: int = UnitPresetBalance.DEFAULT_STAT
@export var shield: int = UnitPresetBalance.DEFAULT_STAT
@export var range_stat: int = UnitPresetBalance.DEFAULT_STAT


static func create_default() -> UnitPreset:
	var preset := UnitPreset.new()
	preset.preset_id = "default"
	preset.preset_name = UnitPresetBalance.default_preset_name()
	preset.is_command = false
	preset.apply_stats_dict(UnitPresetBalance.default_stats())
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
