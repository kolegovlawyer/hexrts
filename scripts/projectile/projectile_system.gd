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

var _next_visual_id: int = 0
var _active_visuals: Dictionary = {} # visual_id -> VisualProjectile (только клиент)
## visual_id -> {volume, radius} — громкость для взрыва без смены show_explosion_at RPC
var _combat_audio_by_visual: Dictionary = {}

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
	var visual_id: int = _allocate_visual_id()
	var projectile = preload("res://scripts/projectile/projectile.gd").new()
	projectile.init(owner_unit, target_position, damage, explosion_radius, visual_id)
	add_child(projectile)
	projectiles.append(projectile)
	
	# Подписываемся на сигнал уничтожения для очистки списка
	projectile.destroyed.connect(_on_projectile_destroyed)
	
	# Отправляем визуальную синхронизацию всем клиентам
	# Клиенты получат только анимацию полета без логики урона
	var shot_linear_volume := _shot_linear_volume_for_unit(owner_unit)
	rpc("create_visual_projectile",
		owner_unit.global_position,
		target_position,
		explosion_radius,
		visual_id,
		shot_linear_volume)

@rpc("any_peer", "call_local", "reliable")
func create_projectile_at_position(
		owner_uid: String,
		target_pos: Vector2,
		damage: int,
		explosion_radius: float = 50.0,
		aim_offset_x: float = 0.0,
		aim_offset_y: float = 0.0
	) -> void:
	if not multiplayer.is_server():
		return
	var owner_unit = Handlers.GameHandler.units_dict.get(owner_uid)
	if not owner_unit or not is_instance_valid(owner_unit):
		return
	var target_position: Vector2 = target_pos + Vector2(aim_offset_x, aim_offset_y)
	var visual_id: int = _allocate_visual_id()
	var projectile = preload("res://scripts/projectile/projectile.gd").new()
	projectile.init(owner_unit, target_position, damage, explosion_radius, visual_id)
	add_child(projectile)
	projectiles.append(projectile)
	projectile.destroyed.connect(_on_projectile_destroyed)
	var shot_linear_volume := _shot_linear_volume_for_unit(owner_unit)
	rpc(
		"create_visual_projectile",
		owner_unit.global_position,
		target_position,
		explosion_radius,
		visual_id,
		shot_linear_volume
	)

## КЛИЕНТСКИЕ ФУНКЦИИ
@rpc("authority", "call_local", "reliable")
func create_visual_projectile(
		start_pos: Vector2,
		target_pos: Vector2,
		explosion_radius: float,
		visual_id: int,
		shot_linear_volume: float = 1.0
	) -> void:
	"""
	Создает визуальный снаряд для клиентов (только анимация).
	shot_linear_volume — косметика: громкость выстрела/взрыва (0.1…1.0), считается на сервере.
	"""
	_combat_audio_by_visual[visual_id] = {
		"volume": shot_linear_volume,
		"radius": explosion_radius,
	}
	# Выстрел: AudioManager no-op на headless; на host/client — позиционный one-shot.
	AudioManager.play_shot(start_pos, shot_linear_volume)

	# Визуальные снаряды — только на клиентах (не на dedicated/listen server process).
	if multiplayer.is_server():
		return

	var visual_projectile = preload("res://scripts/projectile/visual_projectile.gd").new()
	visual_projectile.init_visual(start_pos, target_pos, explosion_radius, visual_id)
	add_child(visual_projectile)
	_active_visuals[visual_id] = visual_projectile

@rpc("authority", "call_local", "reliable")
func finish_visual_projectile(visual_id: int, pos: Vector2) -> void:
	# Взрыв привязан к visual_id (не к show_explosion_at), чтобы не расширять боевой RPC.
	_play_explosion_for_visual(visual_id, pos)
	if multiplayer.is_server():
		return
	var visual: VisualProjectile = _active_visuals.get(visual_id)
	if visual and is_instance_valid(visual):
		visual.finish_at(pos)
	_active_visuals.erase(visual_id)

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


func _shot_linear_volume_for_unit(owner_unit: Node) -> float:
	# DAMAGE_PER_STAT == 1 → unit.damage совпадает с характеристикой атаки 1…20.
	var attack := 5
	if owner_unit.get("damage") != null:
		attack = int(owner_unit.damage)
	return AudioManager.linear_volume_from_attack(attack)


func _play_explosion_for_visual(visual_id: int, pos: Vector2) -> void:
	var audio_data: Variant = _combat_audio_by_visual.get(visual_id)
	_combat_audio_by_visual.erase(visual_id)
	var linear_volume := 1.0
	var radius := 50.0
	if audio_data is Dictionary:
		linear_volume = float(audio_data.get("volume", 1.0))
		radius = float(audio_data.get("radius", 50.0))
	AudioManager.play_explosion(pos, linear_volume, radius)


func _allocate_visual_id() -> int:
	_next_visual_id += 1
	return _next_visual_id


func unregister_visual_projectile(visual_id: int) -> void:
	_active_visuals.erase(visual_id)

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