class_name ExplosionVfx
extends RefCounted

## Общая анимация взрыва для клиентов (снаряд / перехват / visual projectile).

static func spawn_at(parent: Node, pos: Vector2, radius: float) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var explosion_circle := Sprite2D.new()
	var size_px: int = maxi(int(radius * 2.0), 4)
	var explosion_image := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var center := Vector2(radius, radius)
	for x in range(explosion_image.get_width()):
		for y in range(explosion_image.get_height()):
			var pixel_pos := Vector2(x, y)
			var distance: float = center.distance_to(pixel_pos)
			if distance <= radius:
				var intensity: float = 1.0 - (distance / radius)
				var color := Color(1.0, 0.3 + intensity * 0.7, 0.0, intensity * 0.7)
				explosion_image.set_pixel(x, y, color)
	var explosion_texture := ImageTexture.new()
	explosion_texture.set_image(explosion_image)
	explosion_circle.texture = explosion_texture
	explosion_circle.global_position = pos
	explosion_circle.modulate.a = 0.75
	parent.add_child(explosion_circle)
	var cleanup_timer := Timer.new()
	cleanup_timer.wait_time = 0.55
	cleanup_timer.one_shot = true
	cleanup_timer.timeout.connect(explosion_circle.queue_free)
	explosion_circle.add_child(cleanup_timer)
	cleanup_timer.start()
	var tween := explosion_circle.create_tween()
	tween.parallel().tween_property(explosion_circle, "modulate:a", 0.0, 0.45)
	tween.parallel().tween_property(explosion_circle, "scale", Vector2(1.35, 1.35), 0.45)
