class_name BaseUnit extends CharacterBody2D

### БАЗОВЫЙ КЛАСС ДЛЯ ВСЕХ ЮНИТОВ
# Содержит общие свойства и методы, используемые как серверной, так и клиентской логикой

# Общие свойства юнитов
@export var owner_id: int = 1
@export var health: int = 30
@export var shield: int = 15
@export var max_health: int = 30
@export var max_shield: int = 15
@export var UID: String = ""

# Команда юнита
var owner_team = null

# Система видимости
const DEFAULT_VISION_RADIUS := 400.0
var vision_radius: float = DEFAULT_VISION_RADIUS
var visible_by: Array[BaseUnit] = []
var has_vision_on: Array[BaseUnit] = []

# Система приказов
var orders: Array[Dictionary] = []
var current_order: Dictionary = {}

# Состояние юнита
enum UNIT_STATES {
	IDLE,
	MOVING,
	ATTACKING,
	AUTO_ATTACKING
}
var unit_state: int = UNIT_STATES.IDLE

# UI элементы
var preselected: bool = false
var selected: bool = false

# Профиль юнита
var unit_profile = null

# Данные пресета для отображения (имя, номер, иконка)
var preset_display_name: String = ""
var preset_instance_number: int = 0
var preset_icon_path: String = ""

# Сигнал смерти (общий для client/server)
signal unit_died(dead_unit: BaseUnit)

# Флаг командного юнита (для захвата гексов)
var is_command_unit_flag: bool = false

# Базовые методы, которые должны быть реализованы в наследниках
func _ready() -> void:
	add_to_group("units")
	# _ensure_unique_vision_shape вызывается явно из spawner_synchronizer/unit_spawner
	# сразу после spawn, до первого чтения шейдером.
	# Для юнитов вне MultiplayerSpawner (например, в редакторе) делаем deferred-вызов.
	call_deferred("_ensure_unique_vision_shape")
	
func is_valid_unit(unit) -> bool:
	"""Проверяет, что объект существует и является BaseUnit"""
	return unit != null and is_instance_valid(unit) and unit is BaseUnit

func set_vision_radius(new_radius: float) -> void:
	"""Задаёт радиус обзора: дублирует shape, чтобы инстансы не делили один CircleShape2D."""
	vision_radius = new_radius
	_apply_vision_shape_radius(new_radius)
	if is_multiplayer_authority():
		call_deferred("_refresh_visibility_area")

func _ensure_unique_vision_shape() -> void:
	_apply_vision_shape_radius(vision_radius)

func _apply_vision_shape_radius(radius: float) -> void:
	var visibility_area_node: Area2D = get_node_or_null("%VisibilityArea")
	if visibility_area_node == null:
		return
	var vis_shape: CollisionShape2D = visibility_area_node.get_node_or_null("VisibilityShape")
	if vis_shape == null or not vis_shape.shape is CircleShape2D:
		return
	var unique_circle := (vis_shape.shape as CircleShape2D).duplicate() as CircleShape2D
	unique_circle.radius = radius
	vis_shape.shape = unique_circle

func _refresh_visibility_area() -> void:
	var area := get_node_or_null("%VisibilityArea") as Area2D
	if area == null:
		return
	var was_monitoring := area.monitoring
	area.monitoring = false
	area.monitoring = was_monitoring

func _on_unit_died(dead_unit: BaseUnit) -> void:
	"""Удаляет умершего юнита из наших списков"""
	if dead_unit in visible_by:
		visible_by.erase(dead_unit)
	if dead_unit in has_vision_on:
		has_vision_on.erase(dead_unit)

# Виртуальные методы для переопределения в наследниках
func update_visual() -> void:
	"""Обновляет визуальное отображение юнита"""
	pass

func update_health_bar() -> void:
	"""Обновляет полосу здоровья"""
	pass

func update_shield_bar() -> void:
	"""Обновляет полосу щита"""
	pass

func die() -> void:
	"""Обрабатывает смерть юнита"""
	unit_died.emit(self)
	visible_by.clear()
	has_vision_on.clear()
	get_tree().call_group("units", "_on_unit_died", self)
	queue_free()

# Методы состояния для переопределения в наследниках
func _unit_state_exit(_state: int) -> void:
	"""Выход из состояния - очистка и завершение текущих действий"""
	pass

func _unit_state_enter(_state: int) -> void:
	"""Вход в состояние - инициализация поведения"""
	pass

# RPC методы для переопределения в наследниках
@rpc("any_peer", "reliable")
func add_order(_order_obj, _clear_queue: bool = false) -> void:
	"""Добавляет приказ юниту"""
	pass

@rpc("any_peer", "reliable")
func clear_orders() -> void:
	"""Очищает все приказы юнита"""
	pass

@rpc("any_peer", "reliable")
func get_unit_info() -> void:
	"""Возвращает информацию о юните"""
	pass

@rpc("any_peer", "call_local", "reliable")
func sync_health(new_health_value: int) -> void:
	"""Синхронизирует значение здоровья (обновляет локальное отображение)"""
	health = clamp(new_health_value, 0, max_health)
	update_health_bar()

@rpc("any_peer", "call_local", "reliable")
func sync_shield(new_shield_value: int) -> void:
	"""Синхронизирует значение щита (обновляет локальное отображение)"""
	shield = clamp(new_shield_value, 0, max_shield)
	update_shield_bar()

@rpc("any_peer", "reliable")
func set_unit_info(_profile_path: String) -> void:
	"""Устанавливает информацию о профиле юнита"""
	pass

@rpc("authority", "call_local", "reliable")
func sync_preset_stats(
		new_max_health: int,
		new_max_shield: int,
		_new_speed: int,
		_new_damage: int,
		new_vision_radius: float
	) -> void:
	max_health = new_max_health
	max_shield = new_max_shield
	set_vision_radius(new_vision_radius)

func apply_preset_snapshot(_snapshot: Dictionary) -> void:
	pass

@rpc("authority", "call_local", "reliable")
func sync_unit_appearance(display_name: String, instance_number: int, icon_path: String) -> void:
	preset_display_name = display_name
	preset_instance_number = instance_number
	preset_icon_path = icon_path

@rpc("authority", "reliable")
func rpc_apply_damage_to_uid(_target_uid: String, _amount: int, _instigator_uid: String = "") -> void:
	"""Stub: серверный RPC нанесения урона по UID (объявлен на всех пирах для согласованности)"""
	pass

@rpc("authority", "reliable")
func rpc_apply_aoe_damage(_center: Vector2, _radius: float, _amount: int, _instigator_uid: String = "") -> void:
	"""Stub: серверный RPC нанесения AoE урона (объявлен на всех пирах для согласованности)"""
	pass

# Виртуальные методы для переопределения в наследниках
func _physics_process(_delta: float) -> void:
	"""Физический процесс - вызывается каждый фрейм"""
	pass

func get_target_position() -> Vector2:
	"""Возвращает целевую позицию юнита"""
	return global_position

func is_command_unit() -> bool:
	"""Проверяет, является ли юнит командным (для совместимости с bot.gd)"""
	return is_command_unit_flag
