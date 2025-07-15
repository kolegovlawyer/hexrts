extends Node
class_name ProjectileSystem

# Синглтон для управления всеми снарядами в игре
# Отвечает за создание, синхронизацию и уничтожение снарядов

var projectiles: Array[Projectile] = []

func _ready() -> void:
	Handlers.ProjectileHandler = self
	print("🎯 ProjectileSystem инициализирован")

func _exit_tree() -> void:
	Handlers.ProjectileHandler = null

## СЕРВЕРНЫЕ ФУНКЦИИ
@rpc("any_peer", "call_local", "reliable")
func create_projectile(owner_uid: String, target_uid: String, damage: int) -> void:
	"""Создает снаряд на сервере с логикой урона"""
	if not multiplayer.is_server():
		return
		
	print("🚀 ProjectileSystem: Создание снаряда от ", owner_uid, " к ", target_uid)
	
	# Находим владельца и цель
	var owner_unit = Handlers.GameHandler.units_dict.get(owner_uid)
	var target_unit = Handlers.GameHandler.units_dict.get(target_uid)
	
	if not owner_unit or not target_unit:
		print("❌ ProjectileSystem: Не удалось найти юниты для снаряда")
		return
		
	if not is_instance_valid(owner_unit) or not is_instance_valid(target_unit):
		print("❌ ProjectileSystem: Юниты невалидны для снаряда")
		return
	
	# Создаем серверный снаряд
	var projectile = preload("res://scripts/projectile/projectile.gd").new()
	projectile.init(owner_unit, target_unit, damage)
	add_child(projectile)
	projectiles.append(projectile)
	
	# Подключаемся к сигналу уничтожения
	projectile.destroyed.connect(_on_projectile_destroyed)
	
	# Синхронизируем визуальный снаряд для всех клиентов
	rpc("create_visual_projectile", 
		owner_unit.global_position,
		target_unit.global_position,
		target_uid)

## КЛИЕНТСКИЕ ФУНКЦИИ
@rpc("authority", "call_local", "reliable") 
func create_visual_projectile(start_pos: Vector2, target_pos: Vector2, target_uid: String) -> void:
	"""Создает визуальный снаряд для клиентов"""
	if multiplayer.is_server():
		return  # Сервер уже имеет логический снаряд
		
	print("🎨 ProjectileSystem: Создание визуального снаряда для клиента")
	
	# Создаем визуальный снаряд
	var visual_projectile = preload("res://scripts/projectile/visual_projectile.gd").new()
	visual_projectile.init_visual(start_pos, target_pos)
	add_child(visual_projectile)

func _on_projectile_destroyed(projectile: Projectile) -> void:
	"""Удаляет снаряд из списка при уничтожении"""
	if projectile in projectiles:
		projectiles.erase(projectile)
		print("🗑️ ProjectileSystem: Снаряд удален из списка")

func get_projectile_count() -> int:
	"""Возвращает количество активных снарядов"""
	return projectiles.size()

## УТИЛИТАРНЫЕ ФУНКЦИИ
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Очищаем все снаряды при удалении системы
		for projectile in projectiles:
			if is_instance_valid(projectile):
				projectile.queue_free()
		projectiles.clear() 