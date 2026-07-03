class_name UnitIconUtil
extends RefCounted

const ICONS_DIR := "res://assets/all_icons/"

const SIZE_SMALL_MAX_COST := 40
const SIZE_MEDIUM_MAX_COST := 80

## Приоритет при равенстве доминирующих статов.
const DOMINANT_STAT_PRIORITY: Array[String] = ["health", "damage", "range", "shield", "speed"]

const STAT_TO_SHAPE: Dictionary = {
	"health": "cross",
	"damage": "square",
	"range": "star",
	"shield": "diamond",
	"speed": "triangle",
}


static func get_dominant_stat(stats: Dictionary) -> String:
	var best_key := "health"
	var best_value := -1
	for key in DOMINANT_STAT_PRIORITY:
		var value := int(stats.get(key, UnitPresetBalance.DEFAULT_STAT))
		if value > best_value:
			best_value = value
			best_key = key
	return best_key


static func get_size_suffix(cost: int) -> String:
	if cost > SIZE_MEDIUM_MAX_COST:
		return "l"
	if cost >= SIZE_SMALL_MAX_COST:
		return "m"
	return "s"


static func get_icon_path(shape: String, size_suffix: String) -> String:
	return ICONS_DIR + "%s-%s.png" % [shape, size_suffix]


static func get_icon_path_from_stats(stats: Dictionary, is_command: bool) -> String:
	var shape: String = STAT_TO_SHAPE.get(get_dominant_stat(stats), "cross")
	var cost := UnitPresetBalance.calculate_cost(stats, is_command)
	return get_icon_path(shape, get_size_suffix(cost))


static func get_icon_path_for_preset(preset: UnitPreset) -> String:
	return get_icon_path_from_stats(preset.get_stats_dict(), preset.is_command)


static func get_texture_for_preset(preset: UnitPreset) -> Texture2D:
	return load(get_icon_path_for_preset(preset)) as Texture2D


static func get_texture_from_snapshot(snapshot: Dictionary) -> Texture2D:
	var is_command := bool(snapshot.get("is_command", false))
	return load(get_icon_path_from_stats(snapshot, is_command)) as Texture2D
