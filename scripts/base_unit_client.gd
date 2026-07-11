class_name BaseUnitClient extends BaseUnit

### КЛИЕНТСКАЯ ЛОГИКА ЮНИТА
# Содержит только клиентские функции: отображение, UI, обработка ввода
# Коммуницирует с серверной частью через RPC

@onready var selection_ring = get_node("%UnitSelectionRing")
@onready var sprite = get_node("%UnitSelfSprite")
@onready var arrow = get_node("%ArrowSprite")
@onready var health_bar = get_node("%HealthBar")
@onready var shield_bar = get_node("%ShiledBar")
@onready var unit_name_label: Label = get_node_or_null("%UnitName")

### Характеристики для отображения
var _health = 30
var _shield = 15

var frame_group : int
var preview: UnitPreview = null
var _order_queue_snapshot: Array = []
var _hit_flash_tween: Tween = null
var _is_hit_flashing: bool = false

const HIT_FLASH_DURATION: float = 0.2
const _VitalsBarStyle := preload("res://scripts/UI/unit_vitals_bar_style.gd")

var _vitals_bars_styled: bool = false

# Методы для работы с состоянием выделения
func set_preselected(value: bool) -> void:
	preselected = value
	if value == true:
		selection_ring.show()
	else:
		selection_ring.hide()
	_apply_sprite_tint()

func set_selected(value: bool) -> void:
	selected = value
	_update_unit_name_label()
	_apply_sprite_tint()

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

func get_order_queue_snapshot() -> Array:
	return _order_queue_snapshot

func _ready() -> void:
	super._ready()

	# Инициализируем health bar и shield bar
	init_health_bar()
	init_shield_bar()

	if unit_name_label:
		unit_name_label.hide()
		unit_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if not is_multiplayer_authority():
		connect("input_event", handle_input)
		connect("mouse_entered", preseclect)
		connect("mouse_exited", depreselect)

	call_deferred("update_visual")

func _exit_tree() -> void:
	_kill_hit_flash()
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
				# Без Shift — одиночный выбор (как в rack); иначе группа "липнет" и снова даёт scatter
				if Input.is_key_pressed(KEY_SHIFT):
					Handlers.UnitSelectionHandler.add_selected(self)
				else:
					Handlers.UnitSelectionHandler.clear_selection()
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

func _ensure_vitals_bar_styles() -> void:
	if _vitals_bars_styled:
		return
	_VitalsBarStyle.apply_health_bar(health_bar)
	_VitalsBarStyle.apply_shield_bar(shield_bar)
	_vitals_bars_styled = true

func init_health_bar() -> void:
	"""Инициализирует health bar с правильными значениями"""
	# Инициализируем здоровье и щит, если еще не инициализированы
	if _health <= 0:
		_health = max_health
	if _shield <= 0:
		_shield = max_shield

	if health_bar:
		_ensure_vitals_bar_styles()
		health_bar.max_value = max_health
		health_bar.value = _health
		update_health_bar()  # Обновляем отображение с правильными цветами

func update_health_bar() -> void:
	"""Обновляет отображение health bar при изменении здоровья"""
	if health_bar:
		health_bar.value = _health

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
		apply_visual_scale()
		_apply_sprite_tint()
		_update_unit_name_label()
		update_health_bar()
		update_shield_bar()
		_sync_preview_vitals()
		return
	elif Handlers.TeamHandler.find_player_by_id(owner_id).team == Handlers.TeamHandler.my_profile.team:
		apply_unit_icon()
		apply_visual_scale()
		update_sprite_color()
	else:
		apply_unit_icon()
		apply_visual_scale()
		update_sprite_color()
	_update_unit_name_label()
	update_health_bar()
	update_shield_bar()

# === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ РЕФАКТОРИНГА ===

func get_display_name() -> String:
	var base := ""
	if preset_display_name != "" and preset_instance_number > 0:
		base = "%s #%d" % [preset_display_name, preset_instance_number]
	else:
		base = "Командир" if is_command_unit() else "Боец"
		if UID.length() >= 4:
			base = "%s %s" % [base, UID.right(4)]
	if is_command_unit():
		return "%s Командирский" % base
	return base

func _update_unit_name_label() -> void:
	if unit_name_label == null:
		return
	if selected:
		unit_name_label.text = get_display_name()
		unit_name_label.show()
	else:
		unit_name_label.hide()

func apply_unit_icon() -> void:
	if preset_icon_path == "":
		return
	var icon_texture: Texture2D = load(preset_icon_path) as Texture2D
	if icon_texture and sprite:
		sprite.texture = icon_texture


func apply_visual_scale() -> void:
	var cost: int = preset_cost
	if cost <= 0:
		cost = UnitPresetBalance.calculate_cost(
			UnitPresetBalance.default_stats(), is_command_unit()
		)
	var s: float = UnitPresetBalance.visual_scale_for_cost(cost, is_command_unit())
	var v := Vector2(s, s)
	if sprite:
		sprite.scale = v
	if selection_ring:
		selection_ring.scale = v
	# ProgressBar scale идёт от pivot (по умолчанию левый верх) — центрируем относительно юнита.
	_center_bar_pivot_and_scale(health_bar, v)
	_center_bar_pivot_and_scale(shield_bar, v)
	_refresh_unit_tracks()


func _center_bar_pivot_and_scale(bar: Control, scale_v: Vector2) -> void:
	if bar == null:
		return
	var bar_size: Vector2 = bar.size
	if bar_size.x <= 0.0 or bar_size.y <= 0.0:
		bar_size = Vector2(
			absf(bar.offset_right - bar.offset_left),
			absf(bar.offset_bottom - bar.offset_top)
		)
	bar.pivot_offset = bar_size * 0.5
	bar.scale = scale_v


func _ensure_own_preview() -> void:
	if not Handlers.TeamHandler or not Handlers.TeamHandler.my_profile:
		return
	if owner_id != Handlers.TeamHandler.my_profile.PlayerId:
		return
	if not Handlers.UIHandler:
		return

	if preview and is_instance_valid(preview):
		preview = Handlers.UIHandler.get_or_create_unit_preview(self)
		if preview:
			preview.update_visual()
		return
	preview = Handlers.UIHandler.get_or_create_unit_preview(self)

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
	_apply_sprite_tint()

func _is_own_unit_for_tint() -> bool:
	if not Handlers.TeamHandler or not Handlers.TeamHandler.my_profile:
		return false
	return owner_id == Handlers.TeamHandler.my_profile.PlayerId

func _is_enemy_unit_for_tint() -> bool:
	if not Handlers.TeamHandler or not Handlers.TeamHandler.my_profile:
		return false
	if _is_own_unit_for_tint():
		return false
	if owner_team == null:
		return true
	return owner_team != Handlers.TeamHandler.my_profile.team

func _apply_sprite_tint() -> void:
	if sprite == null or _is_hit_flashing:
		return
	if not Handlers.TeamHandler or not Handlers.TeamHandler.my_profile:
		return

	var tint: Color = GameTypes.own_color
	if _is_own_unit_for_tint():
		if selected:
			tint = GameTypes.own_selected_color
		elif preselected:
			tint = GameTypes.own_hover_color
		else:
			tint = GameTypes.own_color
	elif _is_enemy_unit_for_tint():
		if sprite:
			sprite.light_mask = 2
			sprite.visibility_layer = 2
		if preselected:
			tint = GameTypes.enemy_hover_color
		else:
			tint = GameTypes.enemy_color
	else:
		# Союзник (не свой пир)
		tint = GameTypes.ally_color

	sprite.self_modulate = tint

func _kill_hit_flash() -> void:
	if _hit_flash_tween and is_instance_valid(_hit_flash_tween):
		_hit_flash_tween.kill()
	_hit_flash_tween = null
	_is_hit_flashing = false

func _play_hit_flash() -> void:
	if sprite == null:
		return
	_kill_hit_flash()
	_is_hit_flashing = true
	sprite.self_modulate = GameTypes.hit_flash_color
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_interval(HIT_FLASH_DURATION)
	_hit_flash_tween.tween_callback(func() -> void:
		_is_hit_flashing = false
		_hit_flash_tween = null
		_apply_sprite_tint()
	)

## SHIELD BAR FUNCTIONS ##

func init_shield_bar() -> void:
	"""Инициализирует shield bar с правильными значениями"""
	# Инициализируем щит, если еще не инициализирован
	if _shield <= 0:
		_shield = max_shield

	if shield_bar:
		_ensure_vitals_bar_styles()
		shield_bar.max_value = max_shield
		shield_bar.value = _shield
		update_shield_bar()  # Обновляем отображение с правильными цветами

func update_shield_bar() -> void:
	"""Обновляет отображение shield bar при изменении щита"""
	if shield_bar:
		shield_bar.value = _shield
		shield_bar.visible = _shield > 0

func apply_vitals_from_network(
		new_health_value: int,
		new_shield_value: int,
		new_max_health: int = -1,
		new_max_shield: int = -1
	) -> void:
	_apply_synced_vitals(new_health_value, new_shield_value, new_max_health, new_max_shield)

func _apply_synced_vitals(
		new_health_value: int,
		new_shield_value: int,
		new_max_health: int = -1,
		new_max_shield: int = -1
	) -> void:
	if new_max_health > 0:
		max_health = new_max_health
	if new_max_shield > 0:
		max_shield = new_max_shield
	var took_damage: bool = new_health_value < _health or new_shield_value < _shield
	_health = clampi(new_health_value, 0, maxi(1, max_health))
	_shield = clampi(new_shield_value, 0, maxi(0, max_shield))
	health = _health
	shield = _shield
	if health_bar:
		health_bar.max_value = max_health
	if shield_bar:
		shield_bar.max_value = max_shield
	update_health_bar()
	update_shield_bar()
	_sync_preview_vitals()
	if took_damage:
		_play_hit_flash()

@rpc("authority", "call_local", "reliable")
func sync_preset_stats(
		new_max_health: int,
		new_max_shield: int,
		_new_speed: int,
		_new_damage: int,
		new_vision_radius: float,
		new_preset_cost: int = 0
	) -> void:
	# Только caps/vision. Текущие HP/щит приходят через sync_vitals,
	# иначе при позднем reveal враг видит «полный» бар после урона.
	max_health = new_max_health
	max_shield = new_max_shield
	preset_cost = new_preset_cost
	set_vision_radius(new_vision_radius)
	if health_bar:
		health_bar.max_value = max_health
	if shield_bar:
		shield_bar.max_value = max_shield
	update_health_bar()
	update_shield_bar()
	apply_visual_scale()
	if preview and is_instance_valid(preview):
		preview.update_visual()

@rpc("authority", "call_local", "reliable")
func sync_unit_appearance(display_name: String, instance_number: int, icon_path: String) -> void:
	super.sync_unit_appearance(display_name, instance_number, icon_path)
	apply_unit_icon()
	apply_visual_scale()
	_update_unit_name_label()
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

@rpc("authority", "call_local", "reliable")
func sync_order_queue(snapshot: Array) -> void:
	if not is_instance_valid(multiplayer) or owner_id != multiplayer.get_unique_id():
		return
	_order_queue_snapshot = snapshot
	if Handlers.UIHandler and Handlers.UIHandler.has_method("refresh_waypoint_markers"):
		Handlers.UIHandler.refresh_waypoint_markers()
