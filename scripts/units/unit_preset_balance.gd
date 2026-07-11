class_name UnitPresetBalance
extends RefCounted

## Конфиг баланса редактора юнитов. Меняйте значения здесь для тюнинга.

const STAT_MIN := 1
const STAT_MAX := 20
const STAT_SUM_MAX := 40
const DEFAULT_STAT := 5
const STAT_KEYS: Array[String] = ["health", "speed", "damage", "shield", "range"]

const BASE_COST_PER_POINT := 1
const COMMAND_COST_MULTIPLIER := 2.0

## Секунд найма на 1 очко стоимости (25 очков -> 5 сек, 40 -> 8 сек).
const SPAWN_SECONDS_PER_COST_POINT := 0.2

## Перевод очков редактора в игровые значения (дефолт 5 ≈ текущий base_unit).
const HEALTH_PER_STAT := 5
const SHIELD_PER_STAT := 5
const SPEED_PER_STAT := 30
const DAMAGE_PER_STAT := 1
const VISION_RADIUS_PER_STAT := 40

## Множители кривой speed: stat=1 → +200% (×3), stat=20 → mult 0.64 (−20% к прошлому максу).
const SPEED_MULT_AT_MIN := 3.0
const SPEED_MULT_AT_MAX := 0.64

## Множители кривой обзора: stat=1 → +200% (×3), stat=20 → mult 0.81 (−10% к прошлому максу).
const VISION_MULT_AT_MIN := 3.0
const VISION_MULT_AT_MAX := 0.81

## Визуальный масштаб иконки по сумме статов (5 → 0.5×, 40 → 1.5×).
const SCALE_STAT_SUM_MIN := 5
const SCALE_STAT_SUM_MAX := STAT_SUM_MAX
const SCALE_MIN := 0.5
const SCALE_MAX := 1.5

## Время развёртывания КШМ в FOB (секунды).
const DEPLOY_FOB_DURATION := 5.0

## Поворот: лёгкий / тяжёлый юнит (град/с). MASS_MAX = бюджет без speed (STAT_SUM_MAX - STAT_MIN).
const TURN_FAST_DEG := 360.0
const TURN_SLOW_DEG := 90.0
const MASS_MAX := 36.0
const TURN_SPEED_MULT_MIN := 0.7
const TURN_SPEED_MULT_MAX := 1.4

## Множитель скорости в режиме заднего хода (BackMove).
const REVERSE_SPEED_MULT := 0.5

## Половина конуса огня от оси ствола (градусы). Огонь только если цель внутри конуса.
const BARREL_FIRE_HALF_ANGLE_DEG := 35.0

## Пороги суммарного опыта для рангов 1..5 (новый юнит = ранг 0).
const RANK_THRESHOLDS: Array[int] = [40, 100, 180, 280, 400]
## +10% к производным характеристикам за каждый ранг (мультипликативно от базы).
const RANK_BONUS_PER_LEVEL := 0.1
## Стоимость производства ранга 5 → КШМ (0 = награда за ветеранство; может стать >0 при балансе).
const PROMOTION_COST := 0


static func barrel_fire_half_angle_rad() -> float:
	return deg_to_rad(BARREL_FIRE_HALF_ANGLE_DEG)


static func rank_from_experience(xp: int) -> int:
	var result := 0
	for threshold in RANK_THRESHOLDS:
		if xp >= threshold:
			result += 1
		else:
			break
	return result


static func rank_multiplier(unit_rank: int) -> float:
	return 1.0 + RANK_BONUS_PER_LEVEL * float(unit_rank)


static func default_stats() -> Dictionary:
	return {
		"health": DEFAULT_STAT,
		"speed": DEFAULT_STAT,
		"damage": DEFAULT_STAT,
		"shield": DEFAULT_STAT,
		"range": DEFAULT_STAT,
	}


static func is_max_weight(stats: Dictionary) -> bool:
	return sum_stats(stats) == STAT_SUM_MAX


## Статы КШМ при сворачивании стартового FOB (сумма = 40 → можно снова развернуть).
static func starting_fob_pack_stats() -> Dictionary:
	return {
		"health": 5,
		"speed": 20,
		"damage": 5,
		"shield": 5,
		"range": 5,
	}


static func starting_fob_pack_snapshot() -> Dictionary:
	var snapshot := starting_fob_pack_stats()
	snapshot["is_command"] = true
	snapshot["preset_id"] = "packed_starting_fob"
	snapshot["preset_name"] = "КШМ"
	return snapshot


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


static func _curved_stat_value(stat: int, per_stat: int, mult_at_min: float, mult_at_max: float) -> float:
	## Якоря на stat=1 и stat=20; между ними — lerp итогового значения.
	## Нельзя умножать stat на падающий множитель: при mult(20)=0.8 stat=15
	## даёт 15×30×1.38≈621, а stat=20 — только 480.
	var s := float(clamp_stat(stat))
	var value_at_min := float(STAT_MIN) * float(per_stat) * mult_at_min
	var value_at_max := float(STAT_MAX) * float(per_stat) * mult_at_max
	var t := (s - float(STAT_MIN)) / float(STAT_MAX - STAT_MIN)
	return lerpf(value_at_min, value_at_max, t)


static func to_game_speed(stat: int) -> int:
	return int(round(_curved_stat_value(stat, SPEED_PER_STAT, SPEED_MULT_AT_MIN, SPEED_MULT_AT_MAX)))


static func to_game_damage(stat: int) -> int:
	return clamp_stat(stat) * DAMAGE_PER_STAT


static func to_game_vision_radius(stat: int) -> float:
	return _curved_stat_value(stat, VISION_RADIUS_PER_STAT, VISION_MULT_AT_MIN, VISION_MULT_AT_MAX)


## Масса для инерции поворота: всё кроме speed (быстрый юнит не должен быть «тяжёлым»).
static func calc_mass(stats: Dictionary) -> float:
	return float(
		clamp_stat(int(stats.get("health", DEFAULT_STAT)))
		+ clamp_stat(int(stats.get("shield", DEFAULT_STAT)))
		+ clamp_stat(int(stats.get("damage", DEFAULT_STAT)))
		+ clamp_stat(int(stats.get("range", DEFAULT_STAT)))
	)


## Рад/с: масса → неповоротливость, speed_stat → вёрткость.
static func to_game_turn_rate(stats: Dictionary) -> float:
	var mass := calc_mass(stats)
	var mass_t := clampf(mass / MASS_MAX, 0.0, 1.0)
	var base_turn := deg_to_rad(lerpf(TURN_FAST_DEG, TURN_SLOW_DEG, mass_t))
	var speed_stat := float(clamp_stat(int(stats.get("speed", DEFAULT_STAT))))
	var speed_mult := lerpf(TURN_SPEED_MULT_MIN, TURN_SPEED_MULT_MAX, speed_stat / float(STAT_MAX))
	return base_turn * speed_mult


static func validate_spawn_request(stats: Dictionary, is_command: bool, claimed_cost: int) -> bool:
	return calculate_cost(stats, is_command) == claimed_cost


static func get_max_cost(is_command: bool) -> int:
	return STAT_SUM_MAX * get_cost_per_point(is_command)


static func can_increase_stat(stats: Dictionary, stat_key: String) -> bool:
	if sum_stats(stats) >= STAT_SUM_MAX:
		return false
	var current := clamp_stat(int(stats.get(stat_key, DEFAULT_STAT)))
	return current < STAT_MAX


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


static func is_valid_preset_stats(stats: Dictionary, _is_command: bool) -> bool:
	if not are_raw_stats_within_limits(stats):
		return false
	return sum_stats(stats) <= STAT_SUM_MAX


static func stat_sum_from_recruitment_cost(cost: int, is_command: bool) -> int:
	var per_point := get_cost_per_point(is_command)
	if per_point <= 0:
		return 0
	return cost / per_point


static func visual_scale_for_stat_sum(stat_sum: int) -> float:
	var t := 0.0
	if SCALE_STAT_SUM_MAX > SCALE_STAT_SUM_MIN:
		t = clampf(
			float(stat_sum - SCALE_STAT_SUM_MIN) / float(SCALE_STAT_SUM_MAX - SCALE_STAT_SUM_MIN),
			0.0,
			1.0
		)
	return lerpf(SCALE_MIN, SCALE_MAX, t)


static func visual_scale_for_cost(cost: int, is_command: bool) -> float:
	return visual_scale_for_stat_sum(stat_sum_from_recruitment_cost(cost, is_command))
