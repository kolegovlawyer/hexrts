class_name UnitTrackSettings
extends RefCounted

## Снимок параметров следа, собирается из @export ноды UnitTracks.

var sample_distance_px: float = 30.0
var track_color: Color = Color(0.7, 0.7, 0.7, 0.4)
var dissolve_color: Color = Color(1.0, 1.0, 1.0, 0.0)
var line_width: float = 4.0
var line_half_spacing: float = 6.0
var lifetime_sec: float = 5.0
var fade_window_sec: float = 1.5
var max_segments: int = 200


static func fade_factor_for_age(age: float, lifetime: float, fade_window: float) -> float:
	var fade_start: float = maxf(lifetime - fade_window, 0.0)
	if age <= fade_start:
		return 1.0
	if age >= lifetime:
		return 0.0
	return 1.0 - (age - fade_start) / maxf(lifetime - fade_start, 0.001)


static func color_for_fade(track_color: Color, dissolve_color: Color, fade: float) -> Color:
	var t := 1.0 - clampf(fade, 0.0, 1.0)
	var color := track_color.lerp(dissolve_color, t)
	# Подсветка хвоста: при растворении уводим в светлый полупрозрачный, не в тёмный.
	color.r = lerpf(color.r, 1.0, t * 0.85)
	color.g = lerpf(color.g, 1.0, t * 0.85)
	color.b = lerpf(color.b, 1.0, t * 0.85)
	color.a = lerpf(track_color.a, 0.0, t)
	return color
