class_name BaseUnitClient extends BaseUnit

### КЛИЕНТСКАЯ ЛОГИКА ЮНИТА
# Содержит только клиентские функции: отображение, UI, обработка ввода
# Коммуницирует с серверной частью через RPC

@onready var selection_ring = get_node("%UnitSelectionRing")
@onready var sprite = get_node("%UnitSelfSprite")
@onready var arrow = get_node("%ArrowSprite")
@onready var health_bar = get_node("%HealthBar")
@onready var shield_bar = get_node("%ShiledBar")

### Характеристики для отображения
var _health = 30
var _shield = 15

# Методы для работы с состоянием выделения
func set_preselected(value: bool) -> void:
	preselected = value
	if value == true:
		selection_ring.show()
	else:
		selection_ring.hide()

func set_selected(value: bool) -> void:
	selected = value
	if value == true:
		$UnitSelfSprite.self_modulate = Color(0.37, 0.37, 0.37)
	else:
		$UnitSelfSprite.self_modulate = Color(1, 1, 1)

func set_health(value: int) -> void:
	var old_health = _health
	_health = clamp(value, 0, max_health)
	if old_health != _health:
		update_health_bar()

func set_shield(value: int) -> void:
	var old_shield = _shield
	_shield = clamp(value, 0, max_shield)
	if old_shield != _shield:
		update_shield_bar()

var frame_group : int
var preview: UnitPreview = null

func _ready() -> void:
	# Добавляем в группу units для поиска
	add_to_group("units")
	
	# Инициализируем health bar и shield bar
	init_health_bar()
	init_shield_bar()
	
	if not is_multiplayer_authority():
		connect("input_event", handle_input)
		connect("mouse_entered", preseclect)
		connect("mouse_exited", depreselect)

	call_deferred("update_visual")

func _exit_tree() -> void:
	if Handlers.UIHandler and UID != "":
		Handlers.UIHandler.unregister_unit_preview(UID)
	if preview and is_instance_valid(preview):
		preview.queue_free()
	preview = null
	if Handlers.UnitSelectionHandler:
		Handlers.UnitSelectionHandler.remove_unit_from_selection(self)

func preseclect():
	set_preselected(true)
	
func depreselect():
	set_preselected(false)
	
func handle_input(_viewport, _event, _shape_idx):
	if self in get_tree().get_nodes_in_group("own_units"):
		if _event is InputEventMouseButton and _event.button_index == 1:
			if _event.pressed == false:
				selected = true
				Handlers.UnitSelectionHandler.add_selected(self)
				get_viewport().set_input_as_handled()
	else:
		# Атака по правому клику на вражеском юните
		if _event is InputEventMouseButton and _event.button_index == 2:
			if _event.pressed == false:
				if Handlers.UnitSelectionHandler and Handlers.UnitSelectionHandler.has_method("get") and Handlers.UnitSelectionHandler.get("selected_units"):
					for n in Handlers.UnitSelectionHandler.selected_units:
						if is_instance_valid(n):
							n.rpc_id(1, "add_order", UID, true)
				get_viewport().set_input_as_handled()
		# Блокируем UI обработку при любом клике на юните
		elif _event is InputEventMouseButton:
			get_viewport().set_input_as_handled()

## HEALTH BAR FUNCTIONS ##

func init_health_bar() -> void:
	"""Инициализирует health bar с правильными значениями"""
	# Инициализируем здоровье и щит, если еще не инициализированы
	if _health <= 0:
		_health = max_health
	if _shield <= 0:
		_shield = max_shield
	
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = _health
		update_health_bar()  # Обновляем отображение с правильными цветами

func update_health_bar() -> void:
	"""Обновляет отображение health bar при изменении здоровья"""
	if health_bar:
		health_bar.value = _health
		
		# Меняем цвет в зависимости от процента здоровья
		var health_percent = float(_health) / float(max_health)
		if health_percent > 0.7:
			# Зеленый цвет для здорового состояния
			health_bar.modulate = Color.GREEN
		elif health_percent > 0.3:
			# Желтый цвет для поврежденного состояния
			health_bar.modulate = Color.YELLOW
		else:
			# Красный цвет для критического состояния
			health_bar.modulate = Color.RED

func update_visual():
	if not Handlers.TeamHandler or not Handlers.TeamHandler.my_profile:
		return
	if owner_id == 1:
		return
	
	# Сначала проверяем является ли это ботом
	var bot_team = Handlers.GameHandler.get_bot_team_by_id(owner_id) if Handlers.GameHandler else -1
	if bot_team != -1:
		# Это бот - используем команду из системы ботов
		owner_team = bot_team
	else:
		# Это обычный игрок - используем TeamHandler
		var player = Handlers.TeamHandler.find_player_by_id(owner_id)
		if not player:
			return
		owner_team = player.team
	if owner_id == Handlers.TeamHandler.my_profile.PlayerId:
		apply_unit_icon()
		set_own_unit_group()
		_ensure_own_preview()
		update_health_bar()
		update_shield_bar()
		_sync_preview_vitals()
		return
	elif Handlers.TeamHandler.find_player_by_id(owner_id).team == Handlers.TeamHandler.my_profile.team:
		apply_unit_icon()
		update_sprite_color()
	else:
		apply_unit_icon()
		update_sprite_color()
	update_health_bar()
	update_shield_bar()

# === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ РЕФАКТОРИНГА ===

func get_display_name() -> String:
	if preset_display_name != "" and preset_instance_number > 0:
		return "%s #%d" % [preset_display_name, preset_instance_number]
	var base_name := "Командир" if is_command_unit() else "Боец"
	if UID.length() >= 4:
		return "%s %s" % [base_name, UID.right(4)]
	return base_name


func apply_unit_icon() -> void:
	if preset_icon_path == "":
		return
	var icon_texture: Texture2D = load(preset_icon_path) as Texture2D
	if icon_texture and sprite:
		sprite.texture = icon_texture


func _ensure_own_preview() -> void:
	if not Handlers.TeamHandler or not Handlers.TeamHandler.my_profile:
		return
	if owner_id != Handlers.TeamHandler.my_profile.PlayerId:
		return
	if not Handlers.UIHandler:
		return
	if preview and is_instance_valid(preview):
		preview.unit = self
		preview.update_visual()
		return
	var self_preview: UnitPreview = preload("res://prefabs/ui/unit_preview.tscn").instantiate()
	preview = self_preview
	Handlers.UIHandler.unit_container.add_child(preview)
	preview.unit = self
	if UID != "":
		Handlers.UIHandler.register_unit_preview(UID, preview)

func get_current_health() -> int:
	return _health

func get_current_shield() -> int:
	return _shield

func _sync_preview_vitals() -> void:
	if preview and is_instance_valid(preview):
		preview.update_vitals()

func set_own_unit_group():
	if not is_in_group("own_units"):
		add_to_group("own_units")

func set_enemy_unit_group():
	if not is_in_group("enemy_units"):
		add_to_group("enemy_units")

func update_sprite_color():
	if owner_id == Handlers.TeamHandler.my_profile.PlayerId:
		sprite.self_modulate = Color(1, 1, 1)
	elif owner_team == Handlers.TeamHandler.my_profile.team:
		sprite.self_modulate = Color(0, 0, 1)
	else:
		sprite.self_modulate = Color(1, 0, 0)
		if sprite:
			sprite.light_mask = 2
			sprite.visibility_layer = 2

## SHIELD BAR FUNCTIONS ##

func init_shield_bar() -> void:
	"""Инициализирует shield bar с правильными значениями"""
	# Инициализируем щит, если еще не инициализирован
	if _shield <= 0:
		_shield = max_shield
	
	if shield_bar:
		shield_bar.max_value = max_shield
		shield_bar.value = _shield
		update_shield_bar()  # Обновляем отображение с правильными цветами

func update_shield_bar() -> void:
	"""Обновляет отображение shield bar при изменении щита"""
	if shield_bar:
		shield_bar.value = _shield
		
		# Меняем цвет в зависимости от процента щита
		var shield_percent = float(_shield) / float(max_shield)
		if shield_percent > 0.7:
			# Синий цвет для полного щита
			shield_bar.modulate = Color.CYAN
		elif shield_percent > 0.3:
			# Фиолетовый цвет для поврежденного щита
			shield_bar.modulate = Color.MAGENTA
		elif shield_percent > 0:
			# Красный цвет для критического щита
			shield_bar.modulate = Color.ORANGE
		else:
			# Скрываем bar когда щита нет
			shield_bar.modulate = Color.TRANSPARENT

@rpc("any_peer", "call_local", "reliable")
func sync_health(new_health_value: int) -> void:
	"""
	Клиентская реализация: сохраняет бэкинг-поле и обновляет бар
	"""
	_health = clamp(new_health_value, 0, max_health)
	update_health_bar()
	_sync_preview_vitals()

@rpc("any_peer", "call_local", "reliable")
func sync_shield(new_shield_value: int) -> void:
	"""
	Клиентская реализация: сохраняет бэкинг-поле и обновляет бар
	"""
	_shield = clamp(new_shield_value, 0, max_shield)
	update_shield_bar()
	_sync_preview_vitals()

@rpc("authority", "call_local", "reliable")
func sync_preset_stats(
		new_max_health: int,
		new_max_shield: int,
		_new_speed: int,
		_new_damage: int,
		vision_radius: float
	) -> void:
	max_health = new_max_health
	max_shield = new_max_shield
	_health = max_health
	_shield = max_shield

	var visibility_area_node: Area2D = get_node_or_null("%VisibilityArea")
	if visibility_area_node:
		var vis_shape: CollisionShape2D = visibility_area_node.get_node_or_null("VisibilityShape")
		if vis_shape and vis_shape.shape is CircleShape2D:
			vis_shape.shape.radius = vision_radius

	init_health_bar()
	init_shield_bar()

@rpc("authority", "call_local", "reliable")
func sync_unit_appearance(display_name: String, instance_number: int, icon_path: String) -> void:
	super.sync_unit_appearance(display_name, instance_number, icon_path)
	apply_unit_icon()
	if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
		if owner_id == Handlers.TeamHandler.my_profile.PlayerId:
			_ensure_own_preview()
			if preview and is_instance_valid(preview):
				preview.update_visual()

@rpc("any_peer", "reliable")
func set_unit_info(profile_path: String) -> void:
	"""
	Получает информацию о профиле юнита от сервера через RPC
	"""
	if profile_path and profile_path != "":
		unit_profile = load(profile_path)
