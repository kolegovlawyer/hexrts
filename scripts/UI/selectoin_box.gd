extends Area2D

@onready var sprite = get_node("%Sprite")
@onready var collision = get_node("%CollisionShape")

var init_draw_position : Vector2

func _process(delta: float) -> void:
	queue_redraw()
	select_units()

	
func _draw() -> void:
	var lineWidth = 3.0
	var lineColor = Color.WHITE
	var box_size = init_draw_position - Handlers.UIHandler.camera.get_global_mouse_position() 
	draw_rect(Rect2(init_draw_position-box_size, box_size), 
	lineColor, false)
	
func select_units():
	
	var box_size = init_draw_position - Handlers.UIHandler.camera.get_global_mouse_position() 
	var new_rect = 	Rect2(init_draw_position-box_size, box_size)
	collision.position =init_draw_position-box_size/2
	collision.shape.size = abs(new_rect.size)
	
	var units = get_tree().get_nodes_in_group("own_units")
	
	for body in get_overlapping_bodies():
		if body in get_tree().get_nodes_in_group("own_units"):
			if body not in Handlers.UnitSelectionHandler.selected_units:
				Handlers.UnitSelectionHandler.add_selected(body)
				body.selected = true
