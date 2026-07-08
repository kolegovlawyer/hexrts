class_name UnitVitalsBarStyle
extends RefCounted

## Общие цвета и стили полос HP/щита (юнит на карте и в rack).

const COLOR_TRACK: Color = Color("#60607C")
const COLOR_HEALTH: Color = Color("#FF55AE")
const COLOR_SHIELD: Color = Color("#00FFFF")


static func apply_health_bar(bar: ProgressBar) -> void:
	if bar == null:
		return
	bar.modulate = Color.WHITE
	bar.add_theme_stylebox_override("background", _make_style(COLOR_TRACK))
	bar.add_theme_stylebox_override("fill", _make_style(COLOR_HEALTH))


static func apply_shield_bar(bar: ProgressBar) -> void:
	if bar == null:
		return
	bar.modulate = Color.WHITE
	bar.add_theme_stylebox_override("background", _make_style(COLOR_TRACK))
	bar.add_theme_stylebox_override("fill", _make_style(COLOR_SHIELD))


static func _make_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style
