extends Node2D
class_name VisualProjectile

## ВИЗУАЛЬНЫЙ СНАРЯД ДЛЯ КЛИЕНТОВ
# Этот класс предназначен только для отображения полета снаряда на клиентах
# Не содержит логики урона, коллизий или игровой механики
#
# НАЗНАЧЕНИЕ:
# - Синхронизированная анимация полета снаряда
# - Визуальный эффект взрыва по достижении цели
# - Красивый след за снарядом
#
# ОТЛИЧИЯ ОТ СЕРВЕРНОГО СНАРЯДА:
# - Нет проверки коллизий с юнитами
# - Нет логики урона
# - Простая интерполяция от точки A до точки B
# - Существует только на клиентах

# Параметры анимации полета
var start_position: Vector2          # Начальная позиция
var target_position: Vector2         # Конечная позиция (фиксированная)
var speed: float = 600.0             # Скорость анимации
var progress: float = 0.0            # Прогресс полета (0.0 - 1.0)
var explosion_radius: float = 50.0   # Радиус анимации взрыва

var sprite: Sprite2D                 # Спрайт снаряда
var trail: Line2D                    # След полета
var trail_points: Array[Vector2] = [] # Точки следа
var max_trail_length: int = 15       # Максимальная длина следа

func _ready() -> void:
	"""Инициализация визуального снаряда"""
	_create_visual_components()
	# print("🎨 VisualProjectile готов к отображению")  # DEBUG

func _create_visual_components() -> void:
	# Создаем спрайт
	sprite = Sprite2D.new()
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

func init_visual(_start_pos: Vector2, _target_pos: Vector2, _explosion_radius: float = 50.0) -> void:
	start_position = _start_pos
	target_position = _target_pos
	explosion_radius = _explosion_radius
	
	# Добавляем то же смещение, что и для серверного снаряда
	var direction = (target_position - start_position).normalized()
	global_position = start_position + direction * 30.0
	start_position = global_position  # Обновляем начальную позицию
	
	# Направляем снаряд к цели
	if sprite:
		sprite.rotation = direction.angle()

func _process(delta: float) -> void:
	# Анимация полета к целевой позиции
	progress += (speed / start_position.distance_to(target_position)) * delta
	progress = min(progress, 1.0)
	
	# Интерполяция позиции
	global_position = start_position.lerp(target_position, progress)
	
	# Обновляем след
	_update_trail()
	
	# Завершаем полет при достижении цели (взрыв показывает серверный RPC show_explosion_at)
	if progress >= 1.0:
		queue_free()

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