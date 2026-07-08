extends Area2D
class_name Projectile

## СЕРВЕРНЫЙ СНАРЯД С ПОЛНОЙ ЛОГИКОЙ
# Этот класс представляет снаряд, который существует только на сервере
# и содержит всю логику урона, коллизий и взрывов
#
# ОСНОВНЫЕ ПРИНЦИПЫ:
# - Летит к конкретной позиции (не следует за целью)
# - Взрывается при достижении цели или столкновении с врагом
# - Игнорирует союзников (проходит сквозь них)
# - Наносит урон по площади при взрыве
# - Создает визуальную анимацию взрыва
#
# ЖИЗНЕННЫЙ ЦИКЛ:
# 1. Создается через ProjectileSystem.create_projectile()
# 2. Инициализируется с владельцем, целевой позицией и параметрами
# 3. Летит к цели, проверяя коллизии
# 4. Взрывается при достижении цели или столкновении с врагом
# 5. Наносит урон всем вражеским юнитам в радиусе
# 6. Уничтожается и уведомляет ProjectileSystem

# Сигналы для взаимодействия с другими системами
signal hit(target: BaseUnit)           # Устаревший сигнал попадания
signal destroyed(projectile: Projectile)  # Уведомление ProjectileSystem об уничтожении

# Основные параметры снаряда
var projectile_owner: BaseUnit         # Юнит, выпустивший снаряд
var target_position: Vector2           # Целевая позиция полета (фиксированная)
var damage: int = 5                    # Количество урона
var speed: float = 700.0               # Скорость полета в пикселях/сек
var explosion_radius: float = 50.0     # Радиус взрыва в пикселях
const INTERCEPT_RADIUS: float = 18.0   # Радиус перехвата юнита на траектории

# Состояние и визуализация
var is_active: bool = true             # Флаг активности снаряда
var trail_points: Array[Vector2] = []  # Точки для отрисовки следа
var max_trail_length: int = 15         # Максимальная длина следа

# Визуальные компоненты (создаются программно)
var sprite: Sprite2D                   # Спрайт снаряда
var trail: Line2D                      # След полета
var lifetime_timer: Timer              # Таймер автоуничтожения
var collision_shape: CollisionShape2D  # Форма коллизии

func _ready() -> void:
	"""
	Инициализация снаряда при добавлении в сцену
	Создает все необходимые компоненты и подключает сигналы
	"""
	# Создаем все визуальные компоненты программно (спрайт, след, коллизию, таймер)
	_create_visual_components()
	
	# Подключаем обработчики событий
	body_entered.connect(_on_body_entered)        # Столкновение с другими телами
	lifetime_timer.timeout.connect(_on_lifetime_timer_timeout)  # Истечение времени жизни
	
	# print("🚀 Projectile готов к полету")  # DEBUG

func _create_visual_components() -> void:
	# Создаем спрайт
	sprite = Sprite2D.new()
	# Используем простую цветную текстуру
	var image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.YELLOW)
	var texture = ImageTexture.new()
	texture.set_image(image)
	sprite.texture = texture
	sprite.scale = Vector2(1, 1)
	add_child(sprite)
	
	# Создаем след
	trail = Line2D.new()
	trail.width = 2.0
	trail.default_color = Color(1, 1, 0, 0.5)
	add_child(trail)
	
	# Создаем коллизию
	collision_shape = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = 3.0
	collision_shape.shape = circle_shape
	add_child(collision_shape)
	
	# Создаем таймер
	lifetime_timer = Timer.new()
	lifetime_timer.wait_time = 5.0
	lifetime_timer.one_shot = true
	lifetime_timer.autostart = true
	add_child(lifetime_timer)

func init(_projectile_owner: BaseUnit, _target_pos: Vector2, _damage: int, _explosion_radius: float = 50.0) -> void:
	projectile_owner = _projectile_owner
	target_position = _target_pos
	damage = _damage
	explosion_radius = _explosion_radius
	
	# Создаем снаряд с небольшим смещением в сторону цели, чтобы избежать коллизии с владельцем
	var direction = (target_position - projectile_owner.global_position).normalized()
	global_position = projectile_owner.global_position + direction * 30.0  # Смещение на 30 пикселей
	
	print("🎯 Снаряд инициализирован: старт ", global_position, " -> цель ", target_position)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_active:
		_destroy()
		return

	var to_target: Vector2 = target_position - global_position
	var distance_to_target: float = to_target.length()
	var step: float = speed * delta

	# При низком FPS шаг больше радиуса попадания — без этой проверки
	# снаряд перелетает цель и умирает по lifetime без урона.
	if distance_to_target <= maxf(step, 3.0):
		global_position = target_position
		_explode()
		return

	var direction: Vector2 = to_target / distance_to_target
	var next_pos: Vector2 = global_position + direction * step
	var intercept_unit: BaseUnit = _find_unit_on_segment(global_position, next_pos)
	if intercept_unit:
		global_position = intercept_unit.global_position
		_explode()
		return
	
	global_position = next_pos

	_update_trail()

	if sprite:
		sprite.rotation = direction.angle()

func _update_trail() -> void:
	# Добавляем текущую позицию к следу
	trail_points.append(global_position)
	
	# Ограничиваем длину следа
	if trail_points.size() > max_trail_length:
		trail_points.pop_front()
	
	# Обновляем Line2D
	if trail:
		trail.clear_points()
		for point in trail_points:
			trail.add_point(point - global_position)

func _explode() -> void:
	"""
	Взрыв снаряда с уроном по площади
	
	ЛОГИКА ВЗРЫВА:
	1. Проверяет валидность владельца снаряда
	2. Создает визуальную анимацию взрыва
	3. Находит всех юнитов в радиусе взрыва
	4. Фильтрует врагов (исключает владельца и союзников)
	5. Наносит урон всем вражеским юнитам в радиусе
	6. Уничтожает снаряд
	"""
	# print("💥 Снаряд взорвался в позиции ", global_position)  # DEBUG
	
	# Проверяем, что владелец снаряда еще существует
	# Если владелец умер, урон все равно должен проходить
	if not is_instance_valid(projectile_owner):
		# print("⚠️ Владелец снаряда стал невалидным, но взрыв продолжается")  # DEBUG
		pass
	
	# Создаем визуальную анимацию взрыва на клиентах
	if Handlers.ProjectileHandler:
		Handlers.ProjectileHandler.rpc("show_explosion_at", global_position, explosion_radius)
	
	# Собираем всех юнитов, которые попали под взрыв (friendly fire включён)
	var units_in_explosion = []
	var all_units = get_tree().get_nodes_in_group("units")
	
	# Проверяем каждый юнит на карте
	for unit in all_units:
		if not unit or not is_instance_valid(unit) or not (unit is BaseUnit):
			continue
		if unit == projectile_owner:
			continue
		
		var distance = global_position.distance_to(unit.global_position)
		if distance <= explosion_radius:
			# Дополнительная проверка валидности прямо перед нанесением урона
			# (юнит мог умереть между проверками)
			if not is_instance_valid(unit):
				continue
				
			# Проверяем, что владелец снаряда тоже еще валиден
			if not is_instance_valid(projectile_owner):
				continue
			
			# Юнит попал под взрыв - наносим урон
			units_in_explosion.append(unit)
			
			# Передаем владельца снаряда, или null если он стал невалидным
			var damage_dealer = projectile_owner if is_instance_valid(projectile_owner) else null
			unit.apply_damage(damage, damage_dealer)
	
	var all_fobs = get_tree().get_nodes_in_group("fobs")
	for fob_node in all_fobs:
		if not is_instance_valid(fob_node) or not fob_node is fob:
			continue
		if not fob_node.is_alive():
			continue
		if is_instance_valid(projectile_owner) and not _is_enemy_fob(fob_node):
			continue
		var fob_distance = global_position.distance_to(fob_node.global_position)
		if fob_distance <= explosion_radius:
			var fob_damage_dealer = projectile_owner if is_instance_valid(projectile_owner) else null
			fob_node.apply_damage(damage, fob_damage_dealer)
			# print("🔥 Взрыв попал в ", unit.name, " (расстояние: ", int(distance), ")")  # DEBUG
	
	# print("💥 Взрыв поразил ", units_in_explosion.size(), " юнитов")  # DEBUG
	emit_signal("hit", null)  # Уведомляем о попадании
	_destroy()  # Уничтожаем снаряд


func _find_unit_on_segment(segment_start: Vector2, segment_end: Vector2) -> BaseUnit:
	var best_unit: BaseUnit = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("units"):
		if not node is BaseUnit:
			continue
		var unit := node as BaseUnit
		if not is_instance_valid(unit):
			continue
		if unit == projectile_owner:
			continue
		var dist: float = _point_to_segment_distance(unit.global_position, segment_start, segment_end)
		if dist <= INTERCEPT_RADIUS and dist < best_dist:
			best_dist = dist
			best_unit = unit
	return best_unit


func _point_to_segment_distance(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var ab: Vector2 = seg_b - seg_a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.001:
		return point.distance_to(seg_a)
	var t: float = clampf((point - seg_a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(seg_a + ab * t)


func _destroy() -> void:
	is_active = false
	emit_signal("destroyed", self)  # Уведомляем ProjectileSystem
	queue_free()

func _on_body_entered(body: Node2D) -> void:
	"""
	Обработчик столкновения снаряда с другими телами
	
	ЛОГИКА СТОЛКНОВЕНИЙ:
	- Игнорирует владельца снаряда (проходит сквозь него)
	- Игнорирует союзников (дружественный огонь отключен)
	- Взрывается при столкновении с вражескими юнитами
	"""
	# Проверяем, что снаряд активен и столкнулся с юнитом
	if is_active and body is fob:
		var fob_target := body as fob
		if not fob_target.is_alive():
			return
		if _is_enemy_fob(fob_target):
			_explode()
		return
	
	if is_active and body is BaseUnit:
		# Снаряд не может взорваться от владельца
		if body == projectile_owner:
			# print("🔍 Снаряд пролетел мимо владельца: ", body.name)  # DEBUG
			return
		
		# Проверяем принадлежность к команде
		if _is_enemy_unit(body):
			# Столкновение с врагом - взрываемся
			# print("💥 Снаряд столкнулся с врагом: ", body.name)  # DEBUG
			_explode()
		else:
			# Столкновение с союзником - пролетаем дальше
			# print("🤝 Снаряд пролетел мимо союзника: ", body.name)  # DEBUG
			pass

func _is_enemy_unit(unit: BaseUnit) -> bool:
	"""
	Определяет, является ли юнит вражеским по отношению к владельцу снаряда
	
	АЛГОРИТМ ОПРЕДЕЛЕНИЯ:
	1. Сначала проверяет команды через owner_team
	2. Если команды не определены, сравнивает owner_id 
	3. При неопределенности считает юнит вражеским (для безопасности)
	
	ВОЗВРАЩАЕТ:
	- true: Юнит является врагом (можно атаковать)
	- false: Юнит является союзником (атаковать нельзя)
	"""
	# Проверяем валидность объектов
	if not projectile_owner or not is_instance_valid(projectile_owner):
		return true  # Если владелец неизвестен, считаем цель вражеской для безопасности
		
	if not unit or not is_instance_valid(unit):
		return false  # Невалидные юниты не атакуем
	
	# СПОСОБ 1: Сравнение команд через owner_team (основной)
	# Дополнительная проверка валидности перед обращением к свойствам
	if not is_instance_valid(projectile_owner) or not is_instance_valid(unit):
		return true  # Если один из объектов стал невалидным, считаем врагом
		
	if projectile_owner.has_method("get") and unit.has_method("get"):
		var owner_team = projectile_owner.get("owner_team")
		var unit_team = unit.get("owner_team")
		
		if owner_team != null and unit_team != null:
			var is_enemy = owner_team != unit_team
			# print("🔍 ОТЛАДКА: Команда владельца (", owner_team, ") vs команда цели (", unit_team, ") = враг: ", is_enemy)  # DEBUG
			return is_enemy
	
	# СПОСОБ 2: Сравнение через owner_id (резервный)
	var owner_id = projectile_owner.get("owner_id") if projectile_owner.has_method("get") else null
	var unit_owner_id = unit.get("owner_id") if unit.has_method("get") else null
	
	if owner_id != null and unit_owner_id != null:
		var is_enemy = owner_id != unit_owner_id
		# print("🔍 ОТЛАДКА: owner_id владельца (", owner_id, ") vs owner_id цели (", unit_owner_id, ") = враг: ", is_enemy)  # DEBUG
		return is_enemy
	
	# СПОСОБ 3: По умолчанию считаем вражеским (безопасная стратегия)
	return true

func _is_enemy_fob(fob_node: fob) -> bool:
	if not projectile_owner or not is_instance_valid(projectile_owner):
		return true
	if not fob_node or not is_instance_valid(fob_node) or not fob_node.is_alive():
		return false
	if projectile_owner.owner_team != null and fob_node.get_owner_team() != null:
		return projectile_owner.owner_team != fob_node.get_owner_team()
	if projectile_owner.owner_id != 0 and fob_node.owner_id != 0:
		return projectile_owner.owner_id != fob_node.owner_id
	return true

func _on_lifetime_timer_timeout() -> void:
	"""
	Обработчик истечения времени жизни снаряда
	Уничтожает снаряд, если он летел слишком долго (защита от зависших снарядов)
	"""
	# print("⏰ Projectile истек по времени")  # DEBUG
	_destroy()
