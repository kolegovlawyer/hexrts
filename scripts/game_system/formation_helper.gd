class_name FormationHelper
extends RefCounted

## Разброс точек назначения для групповых приказов движения / SpreadButton.
## MVP-константы — позже балансировать под радиус коллайдера (~22) и RVO.

const MOVE_SCATTER_RADIUS: float = 100.0
const SPREAD_DISTANCE: float = 90.0
const MIN_SPACING: float = 55.0


static func scatter_around(
	center: Vector2,
	count: int,
	radius: float = MOVE_SCATTER_RADIUS,
	_min_spacing: float = MIN_SPACING
) -> Array[Vector2]:
	"""Точки вокруг center для count юнитов. Один юнит — точно в center."""
	var result: Array[Vector2] = []
	if count <= 0:
		return result
	if count == 1:
		result.append(center)
		return result

	# Золотой угол — равномерное заполнение диска без стопки в центре
	var golden_angle: float = PI * (3.0 - sqrt(5.0))
	var angle_seed: float = randf() * TAU
	for i in range(count):
		var t: float = float(i) / float(count - 1)
		var r: float = radius * sqrt(t)
		var angle: float = angle_seed + float(i) * golden_angle
		var jitter: float = randf_range(-6.0, 6.0)
		result.append(center + Vector2(cos(angle), sin(angle)) * (r + jitter))
	return result


static func lane_offset(
	lane_index: int,
	lane_count: int,
	radius: float = MOVE_SCATTER_RADIUS
) -> Vector2:
	"""Детерминированный offset для lane_index в группе lane_count (без rand)."""
	if lane_count <= 1 or lane_index < 0 or lane_index >= lane_count:
		return Vector2.ZERO
	var golden_angle: float = PI * (3.0 - sqrt(5.0))
	var t: float = float(lane_index) / float(lane_count - 1)
	var r: float = radius * sqrt(t)
	var angle: float = float(lane_index) * golden_angle
	return Vector2(cos(angle), sin(angle)) * r


static func spread_from_positions(
	positions: Array[Vector2],
	distance: float = SPREAD_DISTANCE
) -> Array[Vector2]:
	"""Точки отъезда от центроида группы. Юниты в куче тоже разъезжаются по кругу."""
	var result: Array[Vector2] = []
	var n: int = positions.size()
	if n == 0:
		return result
	if n == 1:
		var solo_angle: float = randf() * TAU
		result.append(positions[0] + Vector2(cos(solo_angle), sin(solo_angle)) * distance * 0.5)
		return result

	var centroid: Vector2 = Vector2.ZERO
	for p in positions:
		centroid += p
	centroid /= float(n)

	for i in range(n):
		var from_center: Vector2 = positions[i] - centroid
		var dir: Vector2
		if from_center.length_squared() < 4.0:
			var angle: float = (TAU * float(i)) / float(n) + randf() * 0.2
			dir = Vector2(cos(angle), sin(angle))
		else:
			dir = from_center.normalized()
		result.append(positions[i] + dir * distance)

	return result
