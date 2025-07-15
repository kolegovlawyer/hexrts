extends Area2D
class_name Projectile

signal hit(target: BaseUnit)
signal destroyed(projectile: Projectile)  # Сигнал для ProjectileSystem

var projectile_owner: BaseUnit
var target: BaseUnit
var damage: int = 5
var speed: float = 600.0

var is_active: bool = true
var trail_points: Array[Vector2] = []
var max_trail_length: int = 15

var sprite: Sprite2D
var trail: Line2D
var lifetime_timer: Timer
var collision_shape: CollisionShape2D

func _ready() -> void:
	# Создаем визуальные компоненты программно
	_create_visual_components()
	
	# Подключаем сигналы
	body_entered.connect(_on_body_entered)
	lifetime_timer.timeout.connect(_on_lifetime_timer_timeout)
	
	print("🚀 Projectile готов к полету")

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

func init(_projectile_owner: BaseUnit, _target: BaseUnit, _damage: int) -> void:
	projectile_owner = _projectile_owner
	target = _target
	damage = _damage
	global_position = projectile_owner.global_position

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_instance_valid(target) or not is_active:
		_destroy()
		return

	# Движение к цели
	var direction: Vector2 = (target.global_position - global_position).normalized()
	global_position += direction * speed * delta

	# Обновляем след
	_update_trail()
	
	# Вращаем снаряд в сторону движения
	if sprite:
		sprite.rotation = direction.angle()

	# Проверка столкновения с целью
	if global_position.distance_to(target.global_position) < 2.0:
		_hit_target()

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

func _hit_target() -> void:
	emit_signal("hit", target)
	target.apply_damage(damage, projectile_owner)
	print("💥 Projectile попал в цель!")
	_destroy()

func _destroy() -> void:
	is_active = false
	emit_signal("destroyed", self)  # Уведомляем ProjectileSystem
	queue_free()

func _on_body_entered(body: Node2D) -> void:
	# Проверяем столкновение с целью
	if body == target and is_active:
		_hit_target()

func _on_lifetime_timer_timeout() -> void:
	print("⏰ Projectile истек по времени")
	_destroy()
