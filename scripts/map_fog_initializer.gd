extends Node

## ========================================================================
## MAP FOG INITIALIZER - Инициализатор тумана войны на карте
## Настраивает всю систему тумана войны при загрузке карты
## ========================================================================

# Ссылки на компоненты системы тумана войны
@onready var fog_manager = get_parent()  # FogInitializer находится внутри FogOfWarManager
@onready var fog_overlay: ColorRect = get_node("../../FogOfWarLayer/FogOfWarOverlay")

# Ссылка на камеру (находим динамически)
var game_camera: Camera2D

# Ресурсы шейдера
var fog_shader: Shader
var fog_material: ShaderMaterial

func _ready() -> void:
	"""Инициализация системы тумана войны"""
	print("🗺️ MAP_FOG_INIT: Начало инициализации системы тумана войны")
	
	# Загружаем шейдер
	_load_fog_shader()
	
	# Создаем материал
	_create_fog_material()
	
	# ИСПРАВЛЕНИЕ: Отложенная инициализация после загрузки всей сцены
	call_deferred("_initialize_with_delay")

func _initialize_with_delay() -> void:
	"""Отложенная инициализация после полной загрузки сцены"""
	print("🔄 MAP_FOG_INIT: Отложенная инициализация...")
	
	# Находим камеру в сцене (теперь она должна быть загружена)
	_find_game_camera()
	
	# Настраиваем связи
	_setup_fog_system()
	
	print("✅ MAP_FOG_INIT: Система тумана войны успешно инициализирована")

func _load_fog_shader() -> void:
	"""Загружает шейдер тумана войны"""
	fog_shader = load("res://shaders/fog_of_war.gdshader")
	if fog_shader:
		print("📁 MAP_FOG_INIT: Шейдер тумана войны загружен")
	else:
		print("❌ MAP_FOG_INIT: Ошибка загрузки шейдера тумана войны")

func _create_fog_material() -> void:
	"""Создает материал с шейдером тумана войны"""
	if not fog_shader:
		print("❌ MAP_FOG_INIT: Невозможно создать материал - шейдер не загружен")
		return
	
	fog_material = ShaderMaterial.new()
	fog_material.shader = fog_shader
	
	print("🎨 MAP_FOG_INIT: Материал тумана войны создан")

func _find_game_camera() -> void:
	"""Находит игровую камеру в сцене (улучшенная версия)"""
	print("🔍 MAP_FOG_INIT: Поиск игровой камеры...")
	
	# СПОСОБ 1: Через get_viewport().get_camera_2d() (самый надежный)
	var viewport_camera = get_viewport().get_camera_2d()
	if viewport_camera:
		game_camera = viewport_camera
		print("📷 MAP_FOG_INIT: Камера найдена через viewport: ", viewport_camera.name)
		return
	
	# СПОСОБ 2: Ищем по известным путям
	var possible_camera_paths = [
		"/root/Game/Client/Camera2D",  # Основной путь
		"/root/Client/Camera2D",      # Альтернативный путь
		"/root/Game/Camera2D",        # Еще один вариант
	]
	
	for path in possible_camera_paths:
		var camera_node = get_node_or_null(path)
		if camera_node and camera_node is Camera2D:
			game_camera = camera_node
			print("📷 MAP_FOG_INIT: Камера найдена по пути: ", path)
			return
	
	# СПОСОБ 3: Безопасный поиск в дереве сцены
	var root_scene = get_tree().current_scene
	if root_scene:
		game_camera = _find_camera_in_tree(root_scene)
		if game_camera:
			print("📷 MAP_FOG_INIT: Камера найдена в дереве сцены: ", game_camera.name)
			return
	
	# СПОСОБ 4: Поиск среди всех Camera2D в сцене
	var all_cameras = get_tree().get_nodes_in_group("cameras")
	if all_cameras.is_empty():
		# Если группы нет, ищем по типу
		all_cameras = _find_all_cameras_in_scene()
	
	if not all_cameras.is_empty():
		game_camera = all_cameras[0]  # Берем первую найденную
		print("📷 MAP_FOG_INIT: Камера найдена среди всех Camera2D: ", game_camera.name)
		return
	
	print("⚠️ MAP_FOG_INIT: Камера не найдена, система тумана войны может работать некорректно")
	print("💡 MAP_FOG_INIT: Убедитесь что в сцене есть Camera2D узел")

func _find_camera_in_tree(node: Node) -> Camera2D:
	"""Рекурсивно ищет Camera2D в дереве узлов (с защитой от null)"""
	if node == null:
		return null
	
	if node is Camera2D:
		return node
	
	for child in node.get_children():
		var result = _find_camera_in_tree(child)
		if result:
			return result
	
	return null

func _find_all_cameras_in_scene() -> Array:
	"""Находит все Camera2D узлы в сцене"""
	var cameras = []
	var root_scene = get_tree().current_scene
	if root_scene:
		_collect_cameras_recursive(root_scene, cameras)
	return cameras

func _collect_cameras_recursive(node: Node, cameras: Array) -> void:
	"""Рекурсивно собирает все Camera2D узлы"""
	if node == null:
		return
	
	if node is Camera2D:
		cameras.append(node)
	
	for child in node.get_children():
		_collect_cameras_recursive(child, cameras)

func _setup_fog_system() -> void:
	"""Настраивает всю систему тумана войны"""
	if not fog_material or not fog_overlay or not fog_manager:
		print("❌ MAP_FOG_INIT: Не все компоненты найдены для настройки системы")
		return
	
	# Настраиваем параметры менеджера программно
	_configure_fog_manager()
	
	# Применяем материал к ColorRect
	fog_overlay.material = fog_material
	
	# Настраиваем связи в менеджере тумана войны
	fog_manager.setup_fog_rendering(fog_material, fog_overlay, game_camera)
	
	# ИСПРАВЛЕНИЕ: Подключаем сигналы камеры для мгновенного обновления тумана
	_connect_camera_signals()
	
	# Устанавливаем производительность по умолчанию
	fog_manager.set_performance_preset("medium")
	
	print("🔗 MAP_FOG_INIT: Связи системы тумана войны настроены")

func _connect_camera_signals() -> void:
	"""Подключает сигналы камеры для мгновенного обновления тумана войны"""
	if not game_camera:
		print("⚠️ MAP_FOG_INIT: Камера не найдена, сигналы не подключены")
		return
	
	# Подключаем сигналы движения и зума камеры
	if game_camera.has_signal("camera_moved"):
		game_camera.camera_moved.connect(_on_camera_moved)
		print("📡 MAP_FOG_INIT: Подключен сигнал camera_moved")
	
	if game_camera.has_signal("camera_zoomed"):
		game_camera.camera_zoomed.connect(_on_camera_zoomed)
		print("📡 MAP_FOG_INIT: Подключен сигнал camera_zoomed")

func _on_camera_moved() -> void:
	"""Вызывается при движении камеры для мгновенного обновления тумана"""
	if fog_manager:
		fog_manager.force_immediate_update()

func _on_camera_zoomed() -> void:
	"""Вызывается при изменении зума камеры для мгновенного обновления тумана"""
	if fog_manager:
		fog_manager.force_immediate_update()

func _configure_fog_manager() -> void:
	"""Программно настраивает параметры менеджера тумана войны"""
	if not fog_manager:
		return
	
	# Настройки производительности
	fog_manager.max_units_processed = 64
	fog_manager.update_frequency = 0.016
	fog_manager.distance_culling_enabled = true
	fog_manager.max_visibility_distance = 2000.0
	
	# Настройки внешнего вида
	fog_manager.fog_intensity = 0.8
	fog_manager.fog_color = Color(0.2, 0.2, 0.25, 1.0)
	fog_manager.fog_edge_softness = 50.0
	fog_manager.fog_animation_speed = 0.3
	fog_manager.fog_noise_scale = 2.0
	fog_manager.fog_noise_strength = 0.1
	
	print("⚙️ MAP_FOG_INIT: Параметры менеджера тумана войны настроены")

# ========================================================================
# МЕТОДЫ ДЛЯ ВНЕШНЕГО УПРАВЛЕНИЯ
# ========================================================================

func get_fog_manager():
	"""Возвращает менеджер тумана войны"""
	return fog_manager

func set_fog_performance_preset(preset: String) -> void:
	"""Устанавливает предустановку производительности"""
	if fog_manager:
		fog_manager.set_performance_preset(preset)

func toggle_fog_debug() -> void:
	"""Переключает режим отладки тумана"""
	if fog_manager:
		fog_manager.toggle_debug_mode()

func get_fog_debug_info() -> Dictionary:
	"""Возвращает отладочную информацию о тумане"""
	if fog_manager:
		return fog_manager.get_debug_info()
	return {}

# ========================================================================
# МЕТОДЫ ДЛЯ НАСТРОЙКИ ВНЕШНЕГО ВИДА
# ========================================================================

func set_fog_intensity(value: float) -> void:
	"""Устанавливает интенсивность тумана"""
	if fog_manager:
		fog_manager.set_fog_intensity(value)

func set_fog_color(color: Color) -> void:
	"""Устанавливает цвет тумана"""
	if fog_manager:
		fog_manager.set_fog_color(color)

func set_fog_edge_softness(value: float) -> void:
	"""Устанавливает мягкость краев областей видимости"""
	if fog_manager:
		fog_manager.set_fog_edge_softness(value) 
