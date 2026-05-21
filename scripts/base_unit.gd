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

# Сигналы для системы ИИ ботов
signal under_attack(attacker: BaseUnit, victim: BaseUnit)
signal attack_started(attacker: BaseUnit, target: BaseUnit)
signal unit_died(dead_unit: BaseUnit)

# Флаг командного юнита (для захвата гексов)
var is_command_unit_flag: bool = false

# Базовые методы, которые должны быть реализованы в наследниках
func _ready() -> void:
	add_to_group("units")
	
func is_valid_unit(unit) -> bool:
	"""Проверяет, что объект существует и является BaseUnit"""
	return unit != null and is_instance_valid(unit) and unit is BaseUnit

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
func _unit_state_exit(state: int) -> void:
	"""Выход из состояния - очистка и завершение текущих действий"""
	pass

func _unit_state_enter(state: int) -> void:
	"""Вход в состояние - инициализация поведения"""
	pass

# RPC методы для переопределения в наследниках
@rpc("any_peer", "reliable")
func add_order(order_obj, clear_queue: bool = false) -> void:
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
func set_unit_info(profile_path: String) -> void:
	"""Устанавливает информацию о профиле юнита"""
	pass

@rpc("authority", "reliable")
func rpc_apply_damage_to_uid(target_uid: String, amount: int, instigator_uid: String = "") -> void:
	"""Stub: серверный RPC нанесения урона по UID (объявлен на всех пирах для согласованности)"""
	pass

@rpc("authority", "reliable")
func rpc_apply_aoe_damage(center: Vector2, radius: float, amount: int, instigator_uid: String = "") -> void:
	"""Stub: серверный RPC нанесения AoE урона (объявлен на всех пирах для согласованности)"""
	pass

# Виртуальные методы для переопределения в наследниках
func _physics_process(delta: float) -> void:
	"""Физический процесс - вызывается каждый фрейм"""
	pass

func get_target_position() -> Vector2:
	"""Возвращает целевую позицию юнита"""
	return global_position

func is_command_unit() -> bool:
	"""Проверяет, является ли юнит командным (для совместимости с bot.gd)"""
	return is_command_unit_flag
