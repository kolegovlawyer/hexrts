class_name VictoryBalance
extends RefCounted

## Конфиг баланса очков победы и найма. Меняйте значения здесь для тюнинга.

# Пресеты длительности матча, выбираются хостом в лобби (Short / Normal / Long)
enum DurationPreset { SHORT, NORMAL, LONG }

# --- Victory Points (очки победы) ---
# Формула прироста VP в секунду: hexes * VP_LINEAR_COEF - hexes² * VP_QUADRATIC_COEF
# Линейный член: сколько VP/сек даёт каждый контролируемый гекс (чем больше — тем быстрее победа)
const VP_LINEAR_COEF := 0.5
# Квадратичный член: штраф за «перегруз» карты — при большом числе гексов прирост VP замедляется
const VP_QUADRATIC_COEF := 0.0005

# Доля всех гексов карты, которую считаем «средней» при авто-расчёте порога VP к победе
# Пример: при 200 гексах и 0.35 берём ~70 гексов как типичный контроль к середине матча
const AVERAGE_CONTROL_RATIO := 0.35

# Множитель итогового порога VP к победе (0.5 = матч примерно в 2 раза короче по очкам)
const VICTORY_POINTS_TARGET_SCALE := 0.5

# Доля карты (0.0–1.0), которую нужно контролировать для победы по доминации
# 0.70 = победа при удержании 70% гексов
const DOMINATION_PERCENT := 0.70

# --- Recruitment (очки найма юнитов) ---
# Базовый приток очков найма в секунду, даже без контроля гексов
const BASE_RECRUITMENT_RATE := 0.1
# Формула бонуса найма: hexes * RECRUITMENT_LINEAR_COEF - hexes² * RECRUITMENT_QUADRATIC_COEF
# Линейный бонус за каждый контролируемый гекс
const RECRUITMENT_LINEAR_COEF := 0.02
# Квадратичный штраф — при слишком большой территории бонус найма перестаёт расти
const RECRUITMENT_QUADRATIC_COEF := 0.00002
# Максимальный бонус найма от гексов (сверх BASE_RECRUITMENT_RATE), в очках/сек
const RECRUITMENT_BONUS_CAP := 10.0
# Стартовые очки найма у игрока при входе в матч
const INITIAL_RECRUITMENT_POINTS := 1000.0

# Дефолтная длительность матча (минуты) для каждой карты из лобби, если хост не менял preset
const MAP_DEFAULT_DURATION_MINUTES: Dictionary = {
	"test_map": 20.0,       # малая тестовая карта
	"test_world_1": 25.0,   # основная карта с гексовой системой
}

# Запасная длительность (минуты), если имя карты не найдено в MAP_DEFAULT_DURATION_MINUTES
const DEFAULT_MAP_DURATION_MINUTES := 20.0

# Множители к длительности карты в зависимости от выбора хоста в лобби
const DURATION_PRESET_MULTIPLIERS: Dictionary = {
	DurationPreset.SHORT: 0.6,   # ~60% от базовой длительности карты
	DurationPreset.NORMAL: 1.0,   # базовая длительность без изменений
	DurationPreset.LONG: 1.6,    # ~160% от базовой длительности карты
}

# Соответствие имён карт в лобби → путь к .tscn сцены карты
const MAP_SCENE_PATHS: Dictionary = {
	"test_map": "res://scenes/maps/test_map.tscn",
	"test_world_1": "res://scenes/maps/test_world_1.tscn",
}

# Сцена карты по умолчанию, если имя из лобби не распознано
const DEFAULT_MAP_SCENE := "res://scenes/maps/test_world_1.tscn"

# --- Причины завершения матча (строковые ID для логики и экрана Game Over) ---
const REASON_VP_THRESHOLD := "vp_threshold"       # набран порог очков победы
const REASON_DOMINATION := "domination"         # контроль достаточной доли карты
const REASON_TIME_LIMIT := "time_limit"           # истекло время матча
const REASON_FOB_DESTROYED := "fob_destroyed"     # нет FOB и одновременно нет КШМ


static func resolve_map_scene_path(map_name: String) -> String:
	return MAP_SCENE_PATHS.get(map_name, DEFAULT_MAP_SCENE)


static func resolve_match_duration_minutes(map_name: String, duration_preset: int) -> float:
	var base_minutes: float = MAP_DEFAULT_DURATION_MINUTES.get(map_name, DEFAULT_MAP_DURATION_MINUTES)
	var multiplier: float = DURATION_PRESET_MULTIPLIERS.get(duration_preset, 1.0)
	return base_minutes * multiplier


static func calculate_victory_gain(hexes_count: int) -> float:
	if hexes_count <= 0:
		return 0.0
	var gain := float(hexes_count) * VP_LINEAR_COEF - pow(float(hexes_count), 2) * VP_QUADRATIC_COEF
	return maxf(0.0, gain)


static func calculate_recruitment_bonus(hexes_count: int) -> float:
	if hexes_count <= 0:
		return 0.0
	var bonus := float(hexes_count) * RECRUITMENT_LINEAR_COEF - pow(float(hexes_count), 2) * RECRUITMENT_QUADRATIC_COEF
	return clampf(bonus, 0.0, RECRUITMENT_BONUS_CAP)


static func calculate_recruitment_gain(hexes_count: int) -> float:
	return BASE_RECRUITMENT_RATE + calculate_recruitment_bonus(hexes_count)


static func calculate_victory_points_to_win(hex_count: int, match_minutes: float) -> int:
	if hex_count <= 0 or match_minutes <= 0.0:
		return 1000
	var avg_hexes := int(roundf(float(hex_count) * AVERAGE_CONTROL_RATIO))
	var vp_rate := calculate_victory_gain(avg_hexes)
	if vp_rate <= 0.0:
		return 1000
	var raw_target := vp_rate * match_minutes * 60.0
	return maxi(100, int(roundf(raw_target * VICTORY_POINTS_TARGET_SCALE)))


static func get_domination_threshold_hexes(hex_count: int) -> int:
	if hex_count <= 0:
		return 1
	return maxi(1, int(ceilf(float(hex_count) * DOMINATION_PERCENT)))


static func build_active_balance(hex_count: int, map_name: String, duration_preset: int) -> Dictionary:
	var match_minutes := resolve_match_duration_minutes(map_name, duration_preset)
	var victory_points_to_win := calculate_victory_points_to_win(hex_count, match_minutes)
	var domination_hexes := get_domination_threshold_hexes(hex_count)
	return {
		"victory_points_to_win": victory_points_to_win,
		"match_duration_seconds": match_minutes * 60.0,
		"domination_hexes": domination_hexes,
		"total_hexes": hex_count,
		"match_duration_minutes": match_minutes,
	}
