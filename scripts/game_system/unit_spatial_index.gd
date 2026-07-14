class_name UnitSpatialIndex
extends RefCounted
## Пространственный индекс серверных юнитов по гексам OverlayMap.
## Сужает кандидатов для crowd/detour; финальный отбор по distance остаётся у вызывающего.

var _buckets: Dictionary = {} ## Vector2i -> Array
var _map: TileMapLayer = null
var _hex_spacing: float = 256.0
## Переиспользуемые буферы покрытий — без аллокаций в горячем пути.
var _cell_buf: Array[Vector2i] = []
var _frontier: Array[Vector2i] = []
var _next_frontier: Array[Vector2i] = []
var _visited: Dictionary = {}


func is_ready() -> bool:
	return _map != null and is_instance_valid(_map)


func setup(overlay_map: TileMapLayer) -> void:
	_map = overlay_map
	_buckets.clear()
	_hex_spacing = 256.0
	if _map == null:
		return
	var origin := Vector2i.ZERO
	var surrounding: Array[Vector2i] = _map.get_surrounding_cells(origin)
	if not surrounding.is_empty():
		var p0: Vector2 = _map.to_global(_map.map_to_local(origin))
		var p1: Vector2 = _map.to_global(_map.map_to_local(surrounding[0]))
		var dist: float = p0.distance_to(p1)
		if dist > 1.0:
			_hex_spacing = dist


func world_to_cell(world_pos: Vector2) -> Vector2i:
	if not is_ready():
		return Vector2i(2147483647, 2147483647)
	return _map.local_to_map(_map.to_local(world_pos))


func rings_for_radius(radius: float) -> int:
	## Запас ~0.55 * spacing: юнит на границе гекса всё ещё в покрытии соседнего бакета.
	if _hex_spacing <= 1.0:
		return 2
	return maxi(1, int(ceili((radius + _hex_spacing * 0.55) / _hex_spacing)))


func upsert(unit: BaseUnitServer) -> void:
	if unit == null or not is_instance_valid(unit) or not is_ready():
		return
	var cell: Vector2i = world_to_cell(unit.global_position)
	if unit._spatial_registered:
		if cell == unit._spatial_cell:
			return
		_remove_from_bucket(unit._spatial_cell, unit)
	_add_to_bucket(cell, unit)
	unit._spatial_cell = cell
	unit._spatial_registered = true


func remove(unit: BaseUnitServer) -> void:
	if unit == null or not unit._spatial_registered:
		return
	_remove_from_bucket(unit._spatial_cell, unit)
	unit._spatial_registered = false


func collect_in_radius_approx(world_pos: Vector2, radius: float, out: Array) -> void:
	## Заполняет out юнитами из гексов, пересекающих окружность (+ запас).
	## Точный distance_squared_to делает вызывающий код.
	out.clear()
	if not is_ready():
		return
	var center: Vector2i = world_to_cell(world_pos)
	_fill_cells(center, rings_for_radius(radius))
	for cell: Vector2i in _cell_buf:
		var bucket = _buckets.get(cell)
		if bucket == null:
			continue
		for u in bucket:
			if u != null and is_instance_valid(u):
				out.append(u)


func _add_to_bucket(cell: Vector2i, unit: BaseUnitServer) -> void:
	var bucket = _buckets.get(cell)
	if bucket == null:
		bucket = []
		_buckets[cell] = bucket
	if not bucket.has(unit):
		bucket.append(unit)


func _remove_from_bucket(cell: Vector2i, unit: BaseUnitServer) -> void:
	var bucket = _buckets.get(cell)
	if bucket == null:
		return
	bucket.erase(unit)
	if bucket.is_empty():
		_buckets.erase(cell)


func _fill_cells(center: Vector2i, rings: int) -> void:
	_cell_buf.clear()
	_cell_buf.append(center)
	if rings <= 0 or not is_ready():
		return
	_visited.clear()
	_visited[center] = true
	_frontier.clear()
	_frontier.append(center)
	for _r in range(rings):
		_next_frontier.clear()
		for c: Vector2i in _frontier:
			for n: Vector2i in _map.get_surrounding_cells(c):
				if _visited.has(n):
					continue
				_visited[n] = true
				_cell_buf.append(n)
				_next_frontier.append(n)
		_frontier.clear()
		for n2: Vector2i in _next_frontier:
			_frontier.append(n2)
		if _frontier.is_empty():
			break
