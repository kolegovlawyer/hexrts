extends  Camera2D

@export var edge_margin = 100
@export var camera_speed = 400.0
@onready var un_zoomed_viewport_size = get_viewport().size#Vector2(640,360)
var zoom_x = 0.5
var zoom_y = 0.5
var follow_mouse : bool = true
var has_focus : bool = true
var TOP_CORNER
var BOTTOM_CORNER

func set_bounds():
	TOP_CORNER = get_node('/root/Game/Map').get_children()[0].get_node('CameraCornerBottomRight').position
	BOTTOM_CORNER = get_node('/root/Game/Map').get_children()[0].get_node('CameraCornerTopLeft').position

func check_maps_bound(pos):
	if pos.x > TOP_CORNER.x or pos.y > TOP_CORNER.y:
		return false
	elif pos.x < BOTTOM_CORNER.x or pos.y < BOTTOM_CORNER.y:
		return false
	else:
		return true
	

func _process(delta: float) -> void:
	if TOP_CORNER != null and BOTTOM_CORNER != null:
		if check_maps_bound(position) == false:
			return
	
	var move_vector = Vector2.ZERO
	
	# WASD keyboard movement (only when window has focus)
	if has_focus:
		if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
			move_vector.x -= camera_speed * delta
		if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
			move_vector.x += camera_speed * delta
		if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
			move_vector.y -= camera_speed * delta
		if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
			move_vector.y += camera_speed * delta
	
	# Mouse edge movement (only when follow_mouse is enabled and window has focus)
	if follow_mouse == true and has_focus == true:
		var mouse_position = get_viewport().get_mouse_position()
		if mouse_position.x > un_zoomed_viewport_size.x or mouse_position.y > un_zoomed_viewport_size.y or mouse_position.x < 0 or mouse_position.y < 0:
			position += move_vector  # Apply only keyboard movement if mouse is outside viewport
			return
		
		var un_zoomed_viewport_size = get_viewport().size
		#print(mouse_position)
		
		if mouse_position.x <= edge_margin:
			move_vector.x -= camera_speed * delta
		elif mouse_position.x >= un_zoomed_viewport_size.x - edge_margin:
			move_vector.x += camera_speed * delta
		
		if mouse_position.y <= edge_margin:
			move_vector.y -= camera_speed * delta
		elif mouse_position.y >= un_zoomed_viewport_size.y - edge_margin - 100:
			move_vector.y += camera_speed * delta
	
	position += move_vector

func _notification(notification):
	if notification == MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN:
		has_focus = true
		print('Window focused - camera movement enabled')
	elif notification == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT:
		has_focus = false
		print('Window lost focus - camera movement disabled')
	
func _input(event):
	pass
	var mouse_position = get_viewport().get_mouse_position()
	var pre_zoom_value = zoom
	if event is InputEventMouseButton and event.button_index == 5 and event.pressed == true:
		if zoom_x > 0.2:
			zoom_x -= 0.1
			zoom_y -= 0.1
			zoom = Vector2(zoom_x, zoom_y)
			#position += (mouse_position - position) * (Vector2(1,1) - pre_zoom_value / zoom)
	elif event is InputEventMouseButton and event.button_index == 4 and event.pressed==true:
		if zoom_x < 0.8:
			zoom_x += 0.1
			zoom_y += 0.1
			zoom = Vector2(zoom_x, zoom_y)
			#position += (mouse_position - position) * (Vector2(1,1) - pre_zoom_value / zoom)
