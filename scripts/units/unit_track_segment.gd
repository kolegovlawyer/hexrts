class_name UnitTrackSegment
extends Node2D

## Один отрезок следа: две параллельные линии, независимо тухнут без градиента по всему пути.

var _left_line: Line2D
var _right_line: Line2D
var _created_at: float = 0.0
var _settings: UnitTrackSettings
var _from_global: Vector2 = Vector2.ZERO
var _to_global: Vector2 = Vector2.ZERO

static var _fog_manager: FogOfWarManager


func setup(from_global: Vector2, to_global: Vector2, settings: UnitTrackSettings, parent_renderer: Node2D) -> void:
	_settings = settings
	_created_at = _now_sec()
	_from_global = from_global
	_to_global = to_global

	var from_local := parent_renderer.to_local(from_global)
	var to_local_pos := parent_renderer.to_local(to_global)
	var direction := to_local_pos - from_local
	if direction.length_squared() < 0.01:
		queue_free()
		return
	direction = direction.normalized()
	var offset := direction.orthogonal().normalized() * settings.line_half_spacing

	_left_line = _create_line(settings)
	_right_line = _create_line(settings)
	add_child(_left_line)
	add_child(_right_line)

	_left_line.add_point(from_local + offset)
	_left_line.add_point(to_local_pos + offset)
	_right_line.add_point(from_local - offset)
	_right_line.add_point(to_local_pos - offset)

	_apply_fade(0.0, 1.0)
	set_process(true)


func _create_line(settings: UnitTrackSettings) -> Line2D:
	var line := Line2D.new()
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.width = settings.line_width
	line.default_color = settings.track_color
	return line


func _process(_delta: float) -> void:
	if _settings == null:
		queue_free()
		return

	var age := _now_sec() - _created_at
	if age >= _settings.lifetime_sec:
		queue_free()
		return

	var fog_visibility := _get_fog_visibility_factor()
	if fog_visibility <= 0.01:
		if _left_line:
			_left_line.visible = false
		if _right_line:
			_right_line.visible = false
		return

	if _left_line:
		_left_line.visible = true
	if _right_line:
		_right_line.visible = true

	var fade := UnitTrackSettings.fade_factor_for_age(
		age, _settings.lifetime_sec, _settings.fade_window_sec
	)
	_apply_fade(fade, fog_visibility)


func _apply_fade(fade: float, fog_visibility: float) -> void:
	var color := UnitTrackSettings.color_for_fade(
		_settings.track_color, _settings.dissolve_color, fade
	)
	color.a *= fog_visibility
	if _left_line:
		_left_line.default_color = color
	if _right_line:
		_right_line.default_color = color


func _get_fog_visibility_factor() -> float:
	var fog_manager := _find_fog_manager()
	if fog_manager == null:
		return 0.0
	return fog_manager.get_segment_visibility(_from_global, _to_global)


func _find_fog_manager() -> FogOfWarManager:
	if _fog_manager != null and is_instance_valid(_fog_manager):
		return _fog_manager
	_fog_manager = get_tree().root.find_child("FogOfWarManager", true, false) as FogOfWarManager
	return _fog_manager


func _now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0
