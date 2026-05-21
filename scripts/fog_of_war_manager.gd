class_name FogOfWarManager extends Node

## ========================================================================
## FOG OF WAR MANAGER - Управление шейдером тумана войны
## Оптимизированный менеджер для сбора данных юнитов и управления шейдером
## ========================================================================

signal fog_settings_changed() # Сигнал при изменении настроек тумана

# Ссылки на узлы
var fog_material: ShaderMaterial
var fog_color_rect: ColorRect
var camera: Camera2D

# Настройки производительности
@export_group("Performance Settings")
@export var max_units_processed: int = 64 ## Максимальное количество обрабатываемых юнитов
@export var update_frequency: float = 0.0  # 0.0 = каждый фрейм ## Частота обновления (60 FPS = 0.016)
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
var _cached_unit_data: Dictionary = {} # Кэш данных юнитов
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
	print("🌫️ FOG_MANAGER: Инициализация менеджера тумана войны")
	
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
		print("✅ FOG_MANAGER: Начальные настройки применены")

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
	
	print("🔗 FOG_MANAGER: Связи настроены - Material:", fog_material != null, "ColorRect:", fog_color_rect != null, "Camera:", camera != null)
	
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
	
	# Получаем все юниты игрока
	var my_units = get_tree().get_nodes_in_group("own_units")
	if my_units.is_empty():
		return
	
	# ОПТИМИЗАЦИЯ: Находим юниты игрока для определения команды
	var player_team = _get_player_team(my_units[0])
	if player_team == null:
		return
	
	# Собираем все дружественные юниты
	var all_units = get_tree().get_nodes_in_group("units")
	var visible_units: Array[BaseUnit] = []
	
	for unit in all_units:
		if not is_instance_valid(unit) or not unit is BaseUnit:
			continue
			
		# Проверяем принадлежность к команде
		if not _is_ally_unit(unit, player_team):
			continue
		
		# Убираем проверку расстояния до камеры - она больше не нужна
		visible_units.append(unit)
		_debug_units_processed += 1
		
		# Ограничиваем количество обрабатываемых юнитов
		if visible_units.size() >= max_units_processed:
			break
	
	# ИСПРАВЛЕНИЕ: Заполняем массивы МИРОВЫМИ координатами (без преобразования)
	_active_unit_count = min(visible_units.size(), max_units_processed)
	
	for i in range(_active_unit_count):
		var unit = visible_units[i]
		
		# Преобразуем мировые координаты в координаты вьюпорта
		var viewport_pos = camera.get_viewport().get_canvas_transform() * unit.global_position
		
		_unit_positions[i * 2] = viewport_pos.x
		_unit_positions[i * 2 + 1] = viewport_pos.y
		
		# Получаем радиус видимости
		var visibility_radius = 512.0
		if unit.has_node("%VisibilityArea"):
			var visibility_area = unit.get_node("%VisibilityArea")
			if visibility_area.has_node("VisibilityShape"):
				var shape = visibility_area.get_node("VisibilityShape").shape
				if shape is CircleShape2D:
					visibility_radius = shape.radius
		
		# Применяем масштабирование к радиусу для вьюпорта
		_unit_radii[i] = visibility_radius * camera.zoom.x

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
	
	return Handlers.TeamHandler.my_profile.Team

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
			unit_team = player.Team
		else:
			# Проверяем ботов
			var bot_team = _get_bot_team_by_id(unit.owner_id)
			if bot_team != -1:
				unit_team = bot_team
	
	return unit_team == player_team

func _get_bot_team_by_id(player_id: int) -> int:
	"""Получает команду бота по его ID"""
	if not Handlers.GameHandler:
		return -1
	
	for bot in Handlers.GameHandler.active_bots:
		if bot.bot_id == player_id:
			return int(bot.bot_team)
	
	return -1

func _on_viewport_size_changed() -> void:
	"""Обработчик изменения размера viewport"""
	_current_viewport_size = get_viewport().get_visible_rect().size
	print("📏 FOG_MANAGER: Размер viewport изменен на ", _current_viewport_size)

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
	print("🐛 FOG_MANAGER: Режим отладки ", "включен" if _debug_enabled else "выключен")

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
			print("⚠️ FOG_MANAGER: Неизвестная предустановка производительности: ", preset)
			return
	
	print("⚙️ FOG_MANAGER: Установлена предустановка производительности: ", preset.to_upper()) 

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
