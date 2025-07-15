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

# Визуальные компоненты
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
	
	# Завершаем полет при достижении цели
	if progress >= 1.0:
		# print("🎯 VisualProjectile достиг цели, создаем визуальный взрыв")  # DEBUG
		_create_visual_explosion()  # Красивый эффект взрыва
		queue_free()  # Удаляем визуальный снаряд

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

func _create_visual_explosion() -> void:
	"""Создает визуальную анимацию взрыва для клиентов"""
	# Создаем круг взрыва
	var explosion_circle = Sprite2D.new()
	var explosion_image = Image.create(int(explosion_radius * 2), int(explosion_radius * 2), false, Image.FORMAT_RGBA8)
	
	# Рисуем градиентный круг взрыва
	for x in range(explosion_image.get_width()):
		for y in range(explosion_image.get_height()):
			var center = Vector2(explosion_radius, explosion_radius)
			var pixel_pos = Vector2(x, y)
			var distance = center.distance_to(pixel_pos)
			
			if distance <= explosion_radius:
				var intensity = 1.0 - (distance / explosion_radius)
				var color = Color(1.0, 0.3 + intensity * 0.7, 0.0, intensity * 0.6)
				explosion_image.set_pixel(x, y, color)
	
	var explosion_texture = ImageTexture.new()
	explosion_texture.set_image(explosion_image)
	explosion_circle.texture = explosion_texture
	explosion_circle.global_position = global_position
	explosion_circle.modulate.a = 0.7
	
	# Добавляем к родительской сцене
	get_parent().add_child(explosion_circle)
	
	# Создаем таймер для удаления анимации взрыва
	var cleanup_timer = Timer.new()
	cleanup_timer.wait_time = 0.5
	cleanup_timer.one_shot = true
	cleanup_timer.timeout.connect(explosion_circle.queue_free)
	explosion_circle.add_child(cleanup_timer)
	cleanup_timer.start()
	
	# Анимация взрыва (создаем tween от explosion_circle)
	var tween = explosion_circle.create_tween()
	tween.parallel().tween_property(explosion_circle, "modulate:a", 0.0, 0.4)
	tween.parallel().tween_property(explosion_circle, "scale", Vector2(1.3, 1.3), 0.4) 