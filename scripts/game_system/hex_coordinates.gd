class_name HexCoordinates
extends RefCounted

static var _origin: Vector2i = Vector2i.ZERO
static var _grid_min: Vector2i = Vector2i.ZERO
static var _grid_max: Vector2i = Vector2i.ZERO
static var _initialized: bool = false


static func is_initialized() -> bool:
	return _initialized


static func get_grid_min() -> Vector2i:
	return _grid_min


static func get_grid_max() -> Vector2i:
	return _grid_max


static func initialize_from_tile_bounds(tiles: Array) -> void:
	if tiles.is_empty():
		_initialized = false
		return

	var min_x: int = tiles[0].x
	var max_x: int = tiles[0].x
	var min_y: int = tiles[0].y
	var max_y: int = tiles[0].y

	for tile in tiles:
		if not tile is Vector2i:
			continue
		min_x = mini(min_x, tile.x)
		max_x = maxi(max_x, tile.x)
		min_y = mini(min_y, tile.y)
		max_y = maxi(max_y, tile.y)

	_origin = Vector2i(min_x, min_y)
	_grid_min = Vector2i(min_x, min_y)
	_grid_max = Vector2i(max_x, max_y)
	_initialized = true


static func tile_to_label(tile: Vector2i) -> String:
	if not _initialized:
		return "%d,%d" % [tile.x, tile.y]
	var col: int = tile.x - _origin.x
	var row: int = tile.y - _origin.y + 1
	return "%s %d" % [_column_to_letters(col), row]


static func _column_to_letters(col: int) -> String:
	if col < 0:
		return "?"
	var letters := ""
	var index: int = col
	while true:
		letters = char(65 + (index % 26)) + letters
		index = index / 26 - 1
		if index < 0:
			break
	return letters
