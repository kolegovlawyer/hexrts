extends Node2D
class_name Projectile

signal hit(target: BaseUnit)

var projectile_owner: BaseUnit
var target: BaseUnit
var damage: int = 5
var speed: float = 600.0

var is_active: bool = true

func _ready() -> void:
	# Можно добавить визуализацию (например, Sprite)
	pass

func init(_projectile_owner: BaseUnit, _target: BaseUnit, _damage: int) -> void:
	projectile_owner = _projectile_owner
	target = _target
	damage = _damage
	global_position = projectile_owner.global_position

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_instance_valid(target) or not is_active:
		queue_free()
		return

	# Движение к цели
	var direction: Vector2 = (target.global_position - global_position).normalized()
	global_position += direction * speed * delta

	# Проверка столкновения с целью
	if global_position.distance_to(target.global_position) < 12.0:
		emit_signal("hit", target)
		target.apply_damage(damage, projectile_owner) # Метод цели для получения урона
		is_active = false
		queue_free()
