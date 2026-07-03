class_name FogOfWarManager extends Node

## ========================================================================
## FOG OF WAR MANAGER - Управление шейдером тумана войны
## Оптимизированный менеджер для сбора данных юнитов и управления шейдером
## ========================================================================

signal fog_settings_changed()

# Ссылки на узлы
var fog_material: ShaderMaterial
var fog_color_rect: ColorRect
var camera: Camera2D

# Настройки производительности
@export_group("Performance Settings")
@export var max_units_processed: int = 64 ## Максимальное количество обрабатываемых юнитов
@export var update_frequency: float = 0.05  ## 20 Hz; 0.0 = каждый фрейм
# Удаляем неиспользуемые настройки отсечения по расстоянию
#@export var distance_culling_enabled: bool = true
#@export var max_visibility_distance: float = 2000.0

# Настройки тумана
@export_group("Fog Appearance")
@export var fog_intensity: float = 0.8 ## Интенсивность тумана
@export var fog_color: Color = Color(0.2, 0.2, 0.25, 1.0) ## Цвет тумана
@export var fog_edge_softness: float = 50.0 ## Мягкость краев областей видимости
@export var fog_animation_speed: float = 0.3 ## Скорость анимации тумана
@export var fog_noise_scale: float = 2.0 ## Масштаб шума тумана
@export var fog_noise_strength: float = 0.1 ## Сила шума тумана

# Внутренние переменные
var _last_update_time: float = 0.0
var _current_viewport_size: Vector2

# Данные для передачи в шейдер
var _unit_positions: PackedFloat32Array
var _unit_radii: PackedFloat32Array
var _active_unit_count: int = 0

# Отладочная информация
var _debug_enabled: bool = false
var _debug_units_processed: int = 0
var _debug_units_culled: int = 0

func _ready() -> void:
	"""Инициализация менеджера тумана войны"""
	Handlers.dprint("🌫️ FOG_MANAGER: Инициализация")
	
	# Инициализируем массивы для данных юнитов
	_unit_positions = PackedFloat32Array()
	_unit_radii = PackedFloat32Array()
	
	# Резервируем место для максимального количества юнитов
	_unit_positions.resize(max_units_processed * 2) # 2 компонента для Vector2
	_unit_radii.resize(max_units_processed)
	
	# Заполняем нулями
	for i in range(max_units_processed * 2):
		_unit_positions[i] = 0.0
	for i in range(max_units_processed):
		_unit_radii[i] = 0.0
	
	# Получаем размер viewport
	_current_viewport_size = get_viewport().get_visible_rect().size
	
	# Подключаемся к изменениям размера viewport
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	
	# Применяем начальные настройки
	call_deferred("_apply_initial_settings")

func _apply_initial_settings() -> void:
	"""Применяет начальные настройки шейдера"""
	if fog_material:
		_update_shader_settings()
		Handlers.dprint("✅ FOG_MANAGER: Начальные настройки применены")

func setup_fog_rendering(material: ShaderMaterial, color_rect: ColorRect, cam: Camera2D) -> void:
	"""
	Настраивает связи с объектами рендеринга тумана
	
	Параметры:
	- material: ShaderMaterial с загруженным шейдером тумана войны
	- color_rect: ColorRect для отображения тумана
	- cam: Camera2D для получения позиции и зума
	"""
	fog_material = material
	fog_color_rect = color_rect
	camera = cam
	
	Handlers.dprint("🔗 FOG_MANAGER: Связи настроены")
	
	if fog_material:
		_update_shader_settings()

func force_immediate_update() -> void:
	"""Принудительно обновляет туман войны мгновенно (для сигналов камеры)"""
	if fog_material and camera:
		_update_fog_system()

func _process(delta: float) -> void:
	"""Основной цикл обновления менеджера"""
	# ИСПРАВЛЕНИЕ: Обновляем каждый фрейм если update_frequency = 0, иначе с заданной частотой
	if update_frequency <= 0.0:
		_update_fog_system()
	else:
		_last_update_time += delta
		if _last_update_time >= update_frequency:
			_update_fog_system()
			_last_update_time = 0.0

func _update_fog_system() -> void:
	"""Обновляет систему тумана войны"""
	if not fog_material or not camera:
		return
	
	# Обновляем данные камеры
	_update_camera_data()
	
	# Собираем данные видимых юнитов
	_collect_unit_data()
	
	# Передаем данные в шейдер
	_update_shader_data()
	
	# Обновляем настройки шейдера если изменились
	_update_shader_settings()

func _update_camera_data() -> void:
	"""Обновляет данные камеры для преобразования координат"""
	if not camera:
		return
	
	_current_viewport_size = get_viewport().get_visible_rect().size



func _collect_unit_data() -> void:
	"""Собирает данные о юнитах для передачи в шейдер"""
	_debug_units_processed = 0
	_debug_units_culled = 0
	_active_unit_count = 0
	
	# Определяем команду игрока напрямую из профиля (не через own_units)
	# Это позволяет FOB давать обзор даже когда юнитов ещё нет
	if not Handlers.TeamHandler or not Handlers.TeamHandler.my_profile:
		return
	var player_team = Handlers.TeamHandler.my_profile.team
	if player_team == null:
		return
	
	var visible_sources: Array = []
	
	# FOB обрабатываем ПЕРВЫМИ — дают обзор с самого старта игры
	for fob_node in get_tree().get_nodes_in_group("fobs"):
		if visible_sources.size() >= max_units_processed:
			break
		if not is_instance_valid(fob_node) or not fob_node is fob:
			continue
		if not _is_ally_fob(fob_node, player_team):
			continue
		visible_sources.append(fob_node)
		_debug_units_processed += 1
	
	# Затем дружественные юниты
	for unit in get_tree().get_nodes_in_group("units"):
		if visible_sources.size() >= max_units_processed:
			break
		if not is_instance_valid(unit) or not unit is BaseUnit:
			continue
		if not _is_ally_unit(unit, player_team):
			continue
		visible_sources.append(unit)
		_debug_units_processed += 1
	
	_active_unit_count = min(visible_sources.size(), max_units_processed)
	
	for i in range(_active_unit_count):
		var source = visible_sources[i]
		var viewport_pos = camera.get_viewport().get_canvas_transform() * source.global_position
		_unit_positions[i * 2] = viewport_pos.x
		_unit_positions[i * 2 + 1] = viewport_pos.y
		var src_radius := _get_source_vision_radius(source)
		_unit_radii[i] = src_radius * camera.zoom.x

func _update_shader_data() -> void:
	"""Передает данные юнитов в шейдер"""
	if not fog_material:
		return
	
	# Обновляем количество активных юнитов
	fog_material.set_shader_parameter("unit_count", _active_unit_count)
	
	# Обновляем позиции юнитов
	fog_material.set_shader_parameter("unit_positions", _unit_positions)
	
	# Обновляем радиусы видимости
	fog_material.set_shader_parameter("unit_visibility_radii", _unit_radii)
	
	# ИСПРАВЛЕНИЕ: Передаем все данные камеры для преобразования UV → мировые координаты
	fog_material.set_shader_parameter("camera_position", camera.global_position)
	fog_material.set_shader_parameter("camera_zoom", camera.zoom.x)
	fog_material.set_shader_parameter("viewport_size", _current_viewport_size)
	
	# ОТЛАДКА: Печатаем координаты камеры (только когда они изменились)
	if not has_meta("last_camera_pos") or get_meta("last_camera_pos") != camera.global_position:
		set_meta("last_camera_pos", camera.global_position)
		#print("🔍 FOG DEBUG: Camera pos=", camera.global_position, " zoom=", camera.zoom.x, " viewport=", _current_viewport_size)
		if _active_unit_count > 0:
			pass
			#print("🔍 FOG DEBUG: First unit VIEWPORT pos=", Vector2(_unit_positions[0], _unit_positions[1]), " scaled radius=", _unit_radii[0])

func _update_shader_settings() -> void:
	"""Обновляет настройки внешнего вида шейдера"""
	if not fog_material:
		return
	
	fog_material.set_shader_parameter("fog_intensity", fog_intensity)
	fog_material.set_shader_parameter("fog_color", fog_color)
	fog_material.set_shader_parameter("fog_edge_softness", fog_edge_softness)
	fog_material.set_shader_parameter("fog_animation_speed", fog_animation_speed)
	fog_material.set_shader_parameter("fog_noise_scale", fog_noise_scale)
	fog_material.set_shader_parameter("fog_noise_strength", fog_noise_strength)

func _get_player_team(sample_unit: BaseUnit):
	"""Получает команду игрока по образцу юнита"""
	if not is_instance_valid(sample_unit):
		return null
	
	# Используем существующую логику определения команды
	if not Handlers.TeamHandler or not Handlers.TeamHandler.my_profile:
		return null
	
	return Handlers.TeamHandler.my_profile.team

func _is_ally_unit(unit: BaseUnit, player_team) -> bool:
	"""Проверяет является ли юнит союзником"""
	if not is_instance_valid(unit) or player_team == null:
		return false
	
	# Проверяем команду юнита
	var unit_team = null
	
	# Сначала проверяем owner_team (если уже определена)
	if unit.owner_team != null:
		unit_team = unit.owner_team
	else:
		# Пытаемся определить команду через owner_id
		var player = Handlers.TeamHandler.find_player_by_id(unit.owner_id)
		if player:
			unit_team = player.team
		else:
			# Проверяем ботов
			var bot_team = Handlers.GameHandler.get_bot_team_by_id(unit.owner_id) if Handlers.GameHandler else -1
			if bot_team != -1:
				unit_team = bot_team
	
	return unit_team == player_team

func _is_ally_fob(fob_node: fob, player_team) -> bool:
	if not is_instance_valid(fob_node) or player_team == null:
		return false
	if Handlers.TeamHandler == null:
		return false
	var owner_player = Handlers.TeamHandler.find_player_by_id(fob_node.owner_id)
	if owner_player:
		return owner_player.team == player_team
	var bot_team = Handlers.GameHandler.get_bot_team_by_id(fob_node.owner_id) if Handlers.GameHandler else -1
	return bot_team == player_team

func _get_source_vision_radius(source: Node) -> float:
	if source is fob:
		return (source as fob).vision_radius
	if source is BaseUnit:
		return (source as BaseUnit).vision_radius
	return 400.0

func _on_viewport_size_changed() -> void:
	"""Обработчик изменения размера viewport"""
	_current_viewport_size = get_viewport().get_visible_rect().size
	Handlers.dprint("📏 FOG_MANAGER: viewport %s" % _current_viewport_size)

# ========================================================================
# ПУБЛИЧНЫЕ МЕТОДЫ ДЛЯ НАСТРОЙКИ
# ========================================================================

func set_fog_intensity(value: float) -> void:
	"""Устанавливает интенсивность тумана"""
	fog_intensity = clamp(value, 0.0, 1.0)
	if fog_material:
		fog_material.set_shader_parameter("fog_intensity", fog_intensity)

func set_fog_color(value: Color) -> void:
	"""Устанавливает цвет тумана"""
	fog_color = value
	if fog_material:
		fog_material.set_shader_parameter("fog_color", fog_color)

func set_fog_edge_softness(value: float) -> void:
	"""Устанавливает мягкость краев областей видимости"""
	fog_edge_softness = clamp(value, 0.0, 200.0)
	if fog_material:
		fog_material.set_shader_parameter("fog_edge_softness", fog_edge_softness)

func get_debug_info() -> Dictionary:
	"""Возвращает отладочную информацию"""
	return {
		"active_units": _active_unit_count,
		"units_processed": _debug_units_processed,
		"units_culled": _debug_units_culled,
		"max_units": max_units_processed,
		"update_frequency": update_frequency,
		"camera_position": camera.global_position,
		"camera_zoom": camera.zoom.x,
		"viewport_size": _current_viewport_size
	}

func toggle_debug_mode() -> void:
	"""Переключает режим отладки"""
	_debug_enabled = !_debug_enabled
	Handlers.dprint("🐛 FOG_MANAGER: debug %s" % ("on" if _debug_enabled else "off"))

# ========================================================================
# ОПТИМИЗАЦИЯ ПРОИЗВОДИТЕЛЬНОСТИ
# ========================================================================

func set_performance_preset(preset: String) -> void:
	"""
	Устанавливает предустановки производительности
	Варианты: "low", "medium", "high", "ultra"
	"""
	match preset.to_lower():
		"low":
			max_units_processed = 16
			update_frequency = 0.033 # 30 FPS
		"medium":
			max_units_processed = 32
			update_frequency = 0.025 # 40 FPS
		"high":
			max_units_processed = 48
			update_frequency = 0.020 # 50 FPS
		"ultra":
			max_units_processed = 64
			update_frequency = 0.016 # 60 FPS
		_:
			Handlers.dprint("⚠️ FOG_MANAGER: неизвестная предустановка: %s" % preset)
			return
	
	Handlers.dprint("⚙️ FOG_MANAGER: preset %s" % preset.to_upper()) 

func update_shader_camera_data(cam: Camera2D):
	"""
	Обновляет параметры камеры в шейдере (позиция, зум, размер viewport)
	Вызывать из ColorRect/FogOfWarOverlay в _process для синхронизации с рендером
	"""
	if not fog_material or not cam:
		return
	var pos = cam.global_position
	var zoom = cam.zoom.x
	var viewport = get_viewport().get_visible_rect().size
	fog_material.set_shader_parameter("camera_position", pos)
	fog_material.set_shader_parameter("camera_zoom", zoom)
	fog_material.set_shader_parameter("viewport_size", viewport) 
