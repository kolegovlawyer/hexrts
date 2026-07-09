class_name HexBorderOverlay
extends RefCounted

const BORDER_SOURCE_ID := 0
const BORDER_ATLAS_COORDS := Vector2i(0, 0)


static func show_on_main_map(border_map: TileMapLayer, main_map: TileMapLayer) -> void:
	if border_map == null or main_map == null:
		return
	border_map.clear()
	for cell in main_map.get_used_cells():
		border_map.set_cell(cell, BORDER_SOURCE_ID, BORDER_ATLAS_COORDS)


static func hide(border_map: TileMapLayer) -> void:
	if border_map == null:
		return
	border_map.clear()
