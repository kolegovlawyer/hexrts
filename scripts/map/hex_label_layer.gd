class_name HexLabelLayer
extends Node2D

const _HexCoordinatesScript := preload("res://scripts/game_system/hex_coordinates.gd")

const LABEL_FONT_SIZE := 16
const LABEL_COLOR := Color(0.078, 0.078, 0.078, 0.45)

var _overlay_map: TileMapLayer = null
var _label_positions: Array[Vector2] = []
var _label_texts: Array[String] = []
var _font: Font = null


func build_labels(overlay_map: TileMapLayer) -> void:
	clear_labels()
	if overlay_map == null or not _HexCoordinatesScript.is_initialized():
		return

	_overlay_map = overlay_map
	_font = ThemeDB.fallback_font
	var tile_size := overlay_map.tile_set.tile_size
	var half_size := Vector2(tile_size) * 0.5

	# Рисуем через _draw вместо сотен Label — иначе FPS падает и снаряды
	# начинают перелетать цели из-за большого physics-step.
	for x in range(_HexCoordinatesScript.get_grid_min().x, _HexCoordinatesScript.get_grid_max().x + 1):
		for y in range(_HexCoordinatesScript.get_grid_min().y, _HexCoordinatesScript.get_grid_max().y + 1):
			var tile := Vector2i(x, y)
			var text := _HexCoordinatesScript.tile_to_label(tile)
			var local_center := overlay_map.map_to_local(tile) + half_size
			_label_positions.append(local_center)
			_label_texts.append(text)

	queue_redraw()


func clear_labels() -> void:
	_label_positions.clear()
	_label_texts.clear()
	_overlay_map = null
	queue_redraw()


func _draw() -> void:
	if _font == null or _label_positions.is_empty():
		return
	for i in _label_texts.size():
		var text: String = _label_texts[i]
		var center: Vector2 = _label_positions[i]
		var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
		var draw_pos := center - text_size * 0.5 + Vector2(0.0, text_size.y * 0.75)
		draw_string(_font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, LABEL_COLOR)
