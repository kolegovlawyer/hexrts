class_name UnitIconUtil
extends RefCounted

const ICONS_DIR := "res://assets/all_icons/"

## Пороги размера иконки по сумме статов: S 5–20, M 21–35, L 36+.
const SIZE_SMALL_MAX_SUM := 20
const SIZE_MEDIUM_MAX_SUM := 35

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


static func are_all_stats_equal(stats: Dictionary) -> bool:
	var expected := int(stats.get(UnitPresetBalance.STAT_KEYS[0], UnitPresetBalance.DEFAULT_STAT))
	for key in UnitPresetBalance.STAT_KEYS:
		if int(stats.get(key, UnitPresetBalance.DEFAULT_STAT)) != expected:
			return false
	return true


static func get_size_suffix_for_stat_sum(stat_sum: int) -> String:
	if stat_sum > SIZE_MEDIUM_MAX_SUM:
		return "l"
	if stat_sum > SIZE_SMALL_MAX_SUM:
		return "m"
	return "s"


static func get_icon_path(shape: String, size_suffix: String) -> String:
	return ICONS_DIR + "%s-%s.png" % [shape, size_suffix]


static func get_icon_path_from_stats(stats: Dictionary, _is_command: bool = false) -> String:
	var shape := "circle" if are_all_stats_equal(stats) else str(STAT_TO_SHAPE.get(get_dominant_stat(stats), "cross"))
	var stat_sum := UnitPresetBalance.sum_stats(stats)
	return get_icon_path(shape, get_size_suffix_for_stat_sum(stat_sum))


static func get_icon_path_for_preset(preset: UnitPreset) -> String:
	return get_icon_path_from_stats(preset.get_stats_dict(), preset.is_command)


static func get_texture_for_preset(preset: UnitPreset) -> Texture2D:
	return load(get_icon_path_for_preset(preset)) as Texture2D


static func get_texture_from_snapshot(snapshot: Dictionary) -> Texture2D:
	var is_command := bool(snapshot.get("is_command", false))
	return load(get_icon_path_from_stats(snapshot, is_command)) as Texture2D
