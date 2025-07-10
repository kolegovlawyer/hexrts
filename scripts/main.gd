extends Control

@onready var main_tile_map = get_node("%MainTileMap")
@onready var unit = get_node("%Unit")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#print(main_tile_map.get_used_cells())
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_button_pressed() -> void:
	main_tile_map.set_cell(Vector2i(-1, -1), 0, Vector2i(1, 1), 0)
	#var data = main_tile_map.get_cell_tile_data(Vector2i(2, 0))
	#print(data)
	#print('TEST?')
	
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print('test')
		unit.navagent.target_position = get_viewport().get_mouse_position()
