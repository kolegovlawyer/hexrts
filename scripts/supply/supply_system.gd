class_name SupplySystem extends Node
## Линии снабжения: BFS от FOB по гексам команды.
## Пересчёт только по событиям смены владельца / старту матча (не по кадрам).

const SUPPLY_RANGE: int = 1
const OUT_OF_SUPPLY_DELAY: float = 4.0
const RELOAD_PENALTY_MULT: float = 2.0
const CAPTURE_PENALTY_MULT: float = 0.5
## Tint спрайта юнита вне снабжения (hex #40A22B) — пик мерцания
const OUT_OF_SUPPLY_SPRITE_MODULATE := Color("40A22B")
## Период мерцания к цвету вне снабжения (секунды, полный цикл туда-обратно)
const OUT_OF_SUPPLY_PULSE_PERIOD: float = 2.0

## team (int) -> Dictionary[Vector2i, bool]
var supplied_hexes: Dictionary = {}

# Переиспользуемые буферы для BFS (без аллокаций в горячем пути юнита)
var _bfs_queue: Array[Vector2i] = []
var _bfs_visited: Dictionary = {}
var _radius_queue: Array[Vector2i] = []
var _radius_visited: Dictionary = {}
var _radius_dist: Dictionary = {}


func _ready() -> void:
	Handlers.SupplyHandler = self
	name = "SupplySystem"


func _exit_tree() -> void:
	if Handlers.SupplyHandler == self:
		Handlers.SupplyHandler = null


func recalculate_all() -> void:
	"""Пересчитывает снабжение для всех команд, встречающихся на карте."""
	if not Handlers.GameHandler:
		return
	var teams: Dictionary = {}
	teams[0] = true
	teams[1] = true
	for hex in Handlers.GameHandler.hexes_dict.values():
		if hex.team_owner >= 0:
			teams[hex.team_owner] = true
	for team in teams.keys():
		recalculate_team(int(team))


func recalculate_team(team: int) -> void:
	"""BFS от гексов всех живых FOB команды; fallback — вся команда снабжаема."""
	if not Handlers.GameHandler:
		return
	var hexes: Dictionary = Handlers.GameHandler.hexes_dict
	var main_map: TileMapLayer = Handlers.GameHandler.main_map
	var result: Dictionary = {}

	var roots: Array[Vector2i] = _collect_fob_roots(team)
	if roots.is_empty():
		Handlers.dprint(
			"⚠️ SUPPLY: FOB команды", team,
			"не найден или гекс отсутствует — вся команда считается снабжаемой"
		)
		_mark_all_team_hexes_supplied(team, hexes, result)
	elif main_map == null:
		Handlers.dprint(
			"⚠️ SUPPLY: main_map отсутствует — вся команда", team, "считается снабжаемой"
		)
		_mark_all_team_hexes_supplied(team, hexes, result)
	else:
		_bfs_connected_owned(team, roots, hexes, main_map, result)

	supplied_hexes[team] = result
	_apply_is_supplied_flags(team, hexes, result)


func is_hex_supplied(team: int, pos: Vector2i) -> bool:
	if not supplied_hexes.has(team):
		return true
	var team_set: Dictionary = supplied_hexes[team]
	return team_set.has(pos)


func is_unit_supplied(team: int, unit_hex_pos: Vector2i) -> bool:
	"""Юнит снабжаем, если в радиусе SUPPLY_RANGE есть снабжаемый гекс его команды."""
	if not Handlers.GameHandler:
		return true
	var hexes: Dictionary = Handlers.GameHandler.hexes_dict
	var main_map: TileMapLayer = Handlers.GameHandler.main_map
	if main_map == null or not hexes.has(unit_hex_pos):
		return true

	# Быстрый путь: стоим на снабжаемом гексе
	if is_hex_supplied(team, unit_hex_pos):
		return true

	_radius_queue.clear()
	_radius_visited.clear()
	_radius_dist.clear()
	_radius_queue.append(unit_hex_pos)
	_radius_visited[unit_hex_pos] = true
	_radius_dist[unit_hex_pos] = 0
	var head: int = 0

	while head < _radius_queue.size():
		var current: Vector2i = _radius_queue[head]
		head += 1
		var dist: int = int(_radius_dist[current])
		if dist > 0 and is_hex_supplied(team, current):
			return true
		if dist >= SUPPLY_RANGE:
			continue
		for neighbor in main_map.get_surrounding_cells(current):
			if _radius_visited.has(neighbor):
				continue
			if not hexes.has(neighbor):
				continue
			_radius_visited[neighbor] = true
			_radius_dist[neighbor] = dist + 1
			_radius_queue.append(neighbor)

	return false


func get_unsupplied_owned_hexes(team: int) -> Array[Vector2i]:
	"""Гексы команды, принадлежащие ей, но без снабжения (для клиентского оверлея)."""
	var out: Array[Vector2i] = []
	if not Handlers.GameHandler:
		return out
	var team_set: Dictionary = supplied_hexes.get(team, {})
	for pos in Handlers.GameHandler.hexes_dict.keys():
		var hex = Handlers.GameHandler.hexes_dict[pos]
		if hex.team_owner != team:
			continue
		if not team_set.has(pos):
			out.append(pos)
	return out


func _collect_fob_roots(team: int) -> Array[Vector2i]:
	var roots: Array[Vector2i] = []
	if not Handlers.GameHandler:
		return roots
	var seen: Dictionary = {}
	for fob_node in Handlers.GameHandler.get_tree().get_nodes_in_group("fobs"):
		if not is_instance_valid(fob_node):
			continue
		if not fob_node.has_method("is_alive") or not fob_node.is_alive():
			continue
		if not fob_node.has_method("get_owner_team"):
			continue
		var fob_team = fob_node.get_owner_team()
		if fob_team == null or int(fob_team) != team:
			continue
		var hex = Handlers.GameHandler.get_hex_at_world_position(fob_node.global_position)
		if hex == null:
			Handlers.dprint(
				"⚠️ SUPPLY: гекс под FOB", fob_node.name, "команды", team, "не найден"
			)
			continue
		if seen.has(hex.position):
			continue
		seen[hex.position] = true
		roots.append(hex.position)
	return roots


func _mark_all_team_hexes_supplied(team: int, hexes: Dictionary, result: Dictionary) -> void:
	for pos in hexes.keys():
		var hex = hexes[pos]
		if hex.team_owner == team:
			result[pos] = true


func _bfs_connected_owned(
		team: int,
		roots: Array[Vector2i],
		hexes: Dictionary,
		main_map: TileMapLayer,
		result: Dictionary
	) -> void:
	_bfs_queue.clear()
	_bfs_visited.clear()
	for root in roots:
		if not hexes.has(root):
			continue
		# Корень должен принадлежать команде (стартовая территория у FOB)
		if hexes[root].team_owner != team:
			continue
		if _bfs_visited.has(root):
			continue
		_bfs_visited[root] = true
		_bfs_queue.append(root)
		result[root] = true

	var head: int = 0
	while head < _bfs_queue.size():
		var current: Vector2i = _bfs_queue[head]
		head += 1
		for neighbor in main_map.get_surrounding_cells(current):
			if _bfs_visited.has(neighbor):
				continue
			if not hexes.has(neighbor):
				continue
			if hexes[neighbor].team_owner != team:
				continue
			_bfs_visited[neighbor] = true
			result[neighbor] = true
			_bfs_queue.append(neighbor)


func _apply_is_supplied_flags(team: int, hexes: Dictionary, result: Dictionary) -> void:
	for pos in hexes.keys():
		var hex = hexes[pos]
		if hex.team_owner == team:
			hex.is_supplied = result.has(pos)
