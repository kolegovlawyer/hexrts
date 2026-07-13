extends Area2D

@onready var sprite = get_node("%Sprite")
@onready var collision = get_node("%CollisionShape")

var init_draw_position : Vector2

func _process(_delta: float) -> void:
	queue_redraw()
	select_units()

	
func _draw() -> void:
	if Handlers.UIHandler == null or Handlers.UIHandler.camera == null:
		return
	var lineWidth = 3.0
	var lineColor = Color.WHITE
	var box_size = init_draw_position - Handlers.UIHandler.camera.get_global_mouse_position() 
	draw_rect(Rect2(init_draw_position-box_size, box_size), 
	lineColor, false)
	
func select_units():
	if Handlers.UIHandler == null or Handlers.UIHandler.camera == null:
		return
	if Handlers.UnitSelectionHandler == null:
		return

	var box_size = init_draw_position - Handlers.UIHandler.camera.get_global_mouse_position() 
	var new_rect = 	Rect2(init_draw_position-box_size, box_size)
	collision.position =init_draw_position-box_size/2
	collision.shape.size = abs(new_rect.size)
	
	for body in get_overlapping_bodies():
		if not is_instance_valid(body):
			continue
		if body.is_in_group("own_units"):
			if body not in Handlers.UnitSelectionHandler.selected_units:
				Handlers.UnitSelectionHandler.add_selected(body)
