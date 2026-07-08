extends Node
class_name ProjectileSystem

## СИСТЕМА УПРАВЛЕНИЯ СНАРЯДАМИ
# Централизованная система для управления всеми снарядами в игре
# 
# ОТВЕТСТВЕННОСТИ:
# - Создание серверных снарядов с логикой урона
# - Синхронизация визуальных снарядов для клиентов
# - Управление жизненным циклом снарядов
# - Разделение серверной логики и клиентской визуализации
#
# АРХИТЕКТУРА:
# 1. Сервер создает снаряд с реальной логикой урона
# 2. Одновременно отправляет RPC клиентам для визуализации
# 3. Серверный снаряд обрабатывает коллизии и урон
# 4. Клиентские снаряды показывают только анимацию

# Список активных снарядов (только на сервере)
var projectiles: Array[Projectile] = []

const _ExplosionVfxScript := preload("res://scripts/projectile/explosion_vfx.gd")

func _ready() -> void:
	# Регистрируем систему в глобальных обработчиках
	Handlers.ProjectileHandler = self
	# print("🎯 ProjectileSystem инициализирован")  # DEBUG

func _exit_tree() -> void:
	# Очищаем ссылку при удалении
	Handlers.ProjectileHandler = null

## СЕРВЕРНЫЕ ФУНКЦИИ
@rpc("any_peer", "call_local", "reliable")
func create_projectile(
		owner_uid: String,
		target_uid: String,
		damage: int,
		explosion_radius: float = 50.0,
		aim_offset_x: float = 0.0,
		aim_offset_y: float = 0.0
	) -> void:
	"""
	Главная функция создания снарядов - вызывается клиентами через RPC
	
	ПАРАМЕТРЫ:
	- owner_uid: Уникальный ID юнита-стрелка
	- target_uid: Уникальный ID цели 
	- damage: Количество урона
	- explosion_radius: Радиус взрыва в пикселях
	
	ЛОГИКА:
	1. Проверяет, что выполняется на сервере
	2. Находит юнит-владелец по UID
	3. Определяет целевую позицию (где была цель в момент выстрела)
	4. Создает серверный снаряд с логикой урона
	5. Отправляет визуальную синхронизацию всем клиентам
	"""
	# Снаряды с логикой урона создаются только на сервере
	if not multiplayer.is_server():
		return
		
	# print("🚀 ProjectileSystem: Создание снаряда от ", owner_uid, " к ", target_uid)  # DEBUG
	
	# Находим юнит-владелец снаряда по его уникальному ID
	var owner_unit = Handlers.GameHandler.units_dict.get(owner_uid)
	var target_unit = Handlers.GameHandler.units_dict.get(target_uid)
	var target_fob: fob = Handlers.GameHandler.fobs_dict.get(target_uid) if Handlers.GameHandler else null
	
	# Проверяем валидность владельца (обязательно)
	if not owner_unit:
		# print("❌ ProjectileSystem: Не удалось найти владельца снаряда")  # DEBUG
		return
		
	if not is_instance_valid(owner_unit):
		# print("❌ ProjectileSystem: Владелец снаряда невалиден")  # DEBUG
		return
	
	# Определяем целевую позицию для выстрела
	# ВАЖНО: Снаряд летит к позиции цели в момент выстрела, а не следует за движущейся целью
	var target_position: Vector2
	if target_unit and is_instance_valid(target_unit):
		target_position = target_unit.global_position
	elif target_fob and is_instance_valid(target_fob) and target_fob.is_alive():
		target_position = target_fob.global_position
	else:
		# Цель исчезла или умерла - стреляем в направлении по умолчанию
		target_position = owner_unit.global_position + Vector2(100, 0)
		# print("⚠️ Цель не найдена, стреляем в направлении по умолчанию")  # DEBUG
	
	target_position += Vector2(aim_offset_x, aim_offset_y)
	
	# Создаем серверный снаряд с полной логикой (урон, коллизии, взрывы)
	var projectile = preload("res://scripts/projectile/projectile.gd").new()
	projectile.init(owner_unit, target_position, damage, explosion_radius)
	add_child(projectile)
	projectiles.append(projectile)
	
	# Подписываемся на сигнал уничтожения для очистки списка
	projectile.destroyed.connect(_on_projectile_destroyed)
	
	# Отправляем визуальную синхронизацию всем клиентам
	# Клиенты получат только анимацию полета без логики урона
	rpc("create_visual_projectile", 
		owner_unit.global_position,
		target_position,
		explosion_radius)

## КЛИЕНТСКИЕ ФУНКЦИИ
@rpc("authority", "call_local", "reliable") 
func create_visual_projectile(start_pos: Vector2, target_pos: Vector2, explosion_radius: float) -> void:
	"""
	Создает визуальный снаряд для клиентов (только анимация)
	
	ПАРАМЕТРЫ:
	- start_pos: Начальная позиция полета
	- target_pos: Конечная позиция полета  
	- explosion_radius: Радиус анимации взрыва
	
	ВАЖНО: Эта функция вызывается только на клиентах
	Визуальные снаряды не имеют логики урона - только красивая анимация
	"""
	# Визуальные снаряды создаются только на клиентах
	if multiplayer.is_server():
		return  # Сервер уже имеет логический снаряд
		
	# print("🎨 ProjectileSystem: Создание визуального снаряда для клиента")  # DEBUG
	
	# Создаем визуальный снаряд только для отображения
	var visual_projectile = preload("res://scripts/projectile/visual_projectile.gd").new()
	visual_projectile.init_visual(start_pos, target_pos, explosion_radius)
	add_child(visual_projectile)

## ВИЗУАЛЬНЫЙ ВЗРЫВ (клиенты)
@rpc("authority", "call_local", "reliable")
func show_explosion_at(pos: Vector2, radius: float) -> void:
	if multiplayer.is_server():
		return
	_spawn_explosion_at(pos, radius)


static func spawn_explosion_at(parent: Node, pos: Vector2, radius: float) -> void:
	_ExplosionVfxScript.spawn_at(parent, pos, radius)


func _spawn_explosion_at(pos: Vector2, radius: float) -> void:
	_ExplosionVfxScript.spawn_at(self, pos, radius)

## УПРАВЛЕНИЕ ЖИЗНЕННЫМ ЦИКЛОМ
func _on_projectile_destroyed(projectile: Projectile) -> void:
	"""
	Обработчик уничтожения снаряда
	Вызывается автоматически когда снаряд взрывается или истекает по времени
	"""
	if projectile in projectiles:
		projectiles.erase(projectile)
		# print("🗑️ ProjectileSystem: Снаряд удален из списка")  # DEBUG

func get_projectile_count() -> int:
	"""
	Возвращает количество активных снарядов на сервере
	Полезно для отладки и мониторинга производительности
	"""
	return projectiles.size()

## УТИЛИТАРНЫЕ ФУНКЦИИ
func _notification(what: int) -> void:
	"""
	Системное уведомление о состоянии узла
	Обеспечивает корректную очистку при удалении системы
	"""
	if what == NOTIFICATION_PREDELETE:
		# Принудительно уничтожаем все активные снаряды при удалении системы
		for projectile in projectiles:
			if is_instance_valid(projectile):
				projectile.queue_free()
		projectiles.clear() 