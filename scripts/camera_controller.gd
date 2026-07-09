extends  Camera2D

signal camera_moved()
signal camera_zoomed()

@export var edge_margin = 10
@export var camera_speed = 400.0
@export var return_speed = 300.0  # Скорость возврата камеры в границы
@export var observer_mode: bool = false  # Режим наблюдения на dedicated server (без HUD)
@onready var un_zoomed_viewport_size = get_viewport().size#Vector2(640,360)
var zoom_x = 0.5
var zoom_y = 0.5
var follow_mouse : bool = true
var has_focus : bool = true
var TOP_CORNER
var BOTTOM_CORNER
var is_returning : bool = false  # Флаг, указывающий что камера возвращается в границы

# Для оптимизации: отслеживаем предыдущую позицию и зум
var _last_position: Vector2
var _last_zoom: Vector2
var _middle_mouse_dragging: bool = false
var _middle_drag_last_pos: Vector2 = Vector2.ZERO

func _ready():
	# Инициализируем переменные отслеживания
	_last_position = position
	_last_zoom = zoom

func set_observer_mode(enabled: bool) -> void:
	observer_mode = enabled


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
	

func get_clamped_position(pos: Vector2) -> Vector2:
	return Vector2(
		clamp(pos.x, BOTTOM_CORNER.x, TOP_CORNER.x),
		clamp(pos.y, BOTTOM_CORNER.y, TOP_CORNER.y)
	)


func get_visible_world_rect() -> Rect2:
	var half_size := get_viewport().get_visible_rect().size / (2.0 * zoom)
	return Rect2(position - half_size, half_size * 2.0)


func snap_to_world_position(world_pos: Vector2) -> void:
	var target := world_pos
	if TOP_CORNER != null and BOTTOM_CORNER != null:
		target = get_clamped_position(world_pos)
	position = target
	if position != _last_position:
		_last_position = position
		camera_moved.emit()


func _is_pointer_over_blocking_ui() -> bool:
	if Handlers.UIHandler and Handlers.UIHandler.has_method("_is_pointer_over_hud"):
		return Handlers.UIHandler._is_pointer_over_hud()
	return false


func _apply_middle_mouse_drag(delta: Vector2) -> void:
	var world_delta := -delta / zoom
	var new_pos := position + world_delta
	if TOP_CORNER != null and BOTTOM_CORNER != null:
		new_pos = get_clamped_position(new_pos)
	position = new_pos
	if position != _last_position:
		_last_position = position
		camera_moved.emit()


func _end_middle_mouse_drag() -> void:
	_middle_mouse_dragging = false
	follow_mouse = not _is_pointer_over_blocking_ui()

func _process(delta: float) -> void:
	if TOP_CORNER == null or BOTTOM_CORNER == null:
		return
		
	if not check_maps_bound(position):
		is_returning = true
		var target_pos = get_clamped_position(position)
		var direction = (target_pos - position).normalized()
		position += direction * return_speed * delta
		
		# Если мы достаточно близко к целевой позиции, считаем что вернулись
		if position.distance_to(target_pos) < 1.0:
			position = target_pos
			is_returning = false
			
		# Отправляем сигнал о движении камеры
		if position != _last_position:
			_last_position = position
			camera_moved.emit()
		return
	
	if is_returning:
		is_returning = false

	if _middle_mouse_dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_end_middle_mouse_drag()
		
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
		elif mouse_position.y >= un_zoomed_viewport_size.y - edge_margin:
			move_vector.y += camera_speed * delta
	
	# Применяем движение
	var old_position = position
	position += move_vector
	
	# ОПТИМИЗАЦИЯ: Отправляем сигнал только при реальном изменении позиции
	if position != _last_position:
		_last_position = position
		camera_moved.emit()

func _notification(notification):
	if notification == MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN:
		#has_focus = true
		print('Window focused - camera movement enabled')
	elif notification == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT:
		#has_focus = false
		print('Window lost focus - camera movement disabled')
	
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			if not _is_pointer_over_blocking_ui():
				_middle_mouse_dragging = true
				_middle_drag_last_pos = event.position
				follow_mouse = false
		elif _middle_mouse_dragging:
			_end_middle_mouse_drag()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _middle_mouse_dragging:
		var delta: Vector2 = event.position - _middle_drag_last_pos
		_middle_drag_last_pos = event.position
		_apply_middle_mouse_drag(delta)
		get_viewport().set_input_as_handled()
		return

	# Зум через _unhandled_input: колёсико над UI (журнал боя и др.) уже
	# «съедено» Control.accept_event() и сюда не доходит.
	if observer_mode and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		if TOP_CORNER != null and BOTTOM_CORNER != null and check_maps_bound(get_global_mouse_position()):
			position = get_global_mouse_position()
			if position != _last_position:
				_last_position = position
				camera_moved.emit()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if zoom_x > 0.2:
				zoom_x -= 0.1
				zoom_y -= 0.1
				var new_zoom := Vector2(zoom_x, zoom_y)
				zoom = new_zoom
				if new_zoom != _last_zoom:
					_last_zoom = new_zoom
					camera_zoomed.emit()
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if zoom_x < 0.8:
				zoom_x += 0.1
				zoom_y += 0.1
				var new_zoom_up := Vector2(zoom_x, zoom_y)
				zoom = new_zoom_up
				if new_zoom_up != _last_zoom:
					_last_zoom = new_zoom_up
					camera_zoomed.emit()
				get_viewport().set_input_as_handled()
