class_name UnitPresetBalance
extends RefCounted

## Конфиг баланса редактора юнитов. Меняйте значения здесь для тюнинга.

const STAT_MIN := 1
const STAT_MAX := 20
const DEFAULT_STAT := 5
const STAT_KEYS: Array[String] = ["health", "speed", "damage", "shield", "range"]

const BASE_COST_PER_POINT := 1
const COMMAND_COST_MULTIPLIER := 2.0

## Секунд найма на 1 очко стоимости (25 очков -> 5 сек, 100 -> 20 сек).
const SPAWN_SECONDS_PER_COST_POINT := 0.2

## Перевод очков редактора в игровые значения (дефолт 5 ≈ текущий base_unit).
const HEALTH_PER_STAT := 5
const SHIELD_PER_STAT := 5
const SPEED_PER_STAT := 30
const DAMAGE_PER_STAT := 1
const VISION_RADIUS_PER_STAT := 40

## Визуальный масштаб по стоимости пресета.
const NORMAL_COST_MIN := 5
const NORMAL_COST_MAX := 100
const NORMAL_SCALE_MIN := 0.5
const NORMAL_SCALE_MAX := 1.5

const COMMAND_COST_MIN := 10
const COMMAND_COST_MAX := 200
const COMMAND_SCALE_MIN := 1.0
const COMMAND_SCALE_MAX := 2.0


static func default_stats() -> Dictionary:
	return {
		"health": DEFAULT_STAT,
		"speed": DEFAULT_STAT,
		"damage": DEFAULT_STAT,
		"shield": DEFAULT_STAT,
		"range": DEFAULT_STAT,
	}


static func default_preset_name() -> String:
	return "Боец"


static func get_cost_per_point(is_command: bool) -> int:
	if is_command:
		return int(BASE_COST_PER_POINT * COMMAND_COST_MULTIPLIER)
	return BASE_COST_PER_POINT


static func sum_stats(stats: Dictionary) -> int:
	var total := 0
	for key in STAT_KEYS:
		total += clamp_stat(int(stats.get(key, DEFAULT_STAT)))
	return total


static func calculate_cost(stats: Dictionary, is_command: bool) -> int:
	return sum_stats(stats) * get_cost_per_point(is_command)


static func calculate_spawn_time(cost: int) -> float:
	return float(cost) * SPAWN_SECONDS_PER_COST_POINT


static func clamp_stat(value: int) -> int:
	return clampi(value, STAT_MIN, STAT_MAX)


static func to_game_health(stat: int) -> int:
	return clamp_stat(stat) * HEALTH_PER_STAT


static func to_game_shield(stat: int) -> int:
	return clamp_stat(stat) * SHIELD_PER_STAT


static func to_game_speed(stat: int) -> int:
	return clamp_stat(stat) * SPEED_PER_STAT


static func to_game_damage(stat: int) -> int:
	return clamp_stat(stat) * DAMAGE_PER_STAT


static func to_game_vision_radius(stat: int) -> float:
	return float(clamp_stat(stat)) * VISION_RADIUS_PER_STAT


static func validate_spawn_request(stats: Dictionary, is_command: bool, claimed_cost: int) -> bool:
	return calculate_cost(stats, is_command) == claimed_cost


static func get_max_cost(is_command: bool) -> int:
	var max_stat_sum := STAT_MAX * STAT_KEYS.size()
	return max_stat_sum * get_cost_per_point(is_command)


static func are_raw_stats_within_limits(stats: Dictionary) -> bool:
	for key in STAT_KEYS:
		if not stats.has(key):
			return false
		if typeof(stats[key]) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		var value := int(stats[key])
		if value < STAT_MIN or value > STAT_MAX:
			return false
	return true


static func is_valid_preset_stats(stats: Dictionary, is_command: bool) -> bool:
	if not are_raw_stats_within_limits(stats):
		return false
	return calculate_cost(stats, is_command) <= get_max_cost(is_command)


static func visual_scale_for_cost(cost: int, is_command: bool) -> float:
	var c_min: int = COMMAND_COST_MIN if is_command else NORMAL_COST_MIN
	var c_max: int = COMMAND_COST_MAX if is_command else NORMAL_COST_MAX
	var s_min: float = COMMAND_SCALE_MIN if is_command else NORMAL_SCALE_MIN
	var s_max: float = COMMAND_SCALE_MAX if is_command else NORMAL_SCALE_MAX
	var t := 0.0
	if c_max > c_min:
		t = clampf(float(cost - c_min) / float(c_max - c_min), 0.0, 1.0)
	return lerpf(s_min, s_max, t)
