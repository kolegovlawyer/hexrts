class_name UnitTrackRenderer
extends Node2D

## Один canvas item на юнита: все сегменты следа рисуются в _draw без дочерних нод.

const TRACK_FOG_REFRESH_SEC: float = 0.15
## Пересчёт fade/цвета при изменении фактора больше порога (или вместе с fog-тиком).
const TRACK_FADE_RECALC_EPS: float = 0.02

var _settings: UnitTrackSettings = UnitTrackSettings.new()
var _segments: Array[UnitTrackSegmentData] = []
var _sampling_enabled: bool = true
var _fog_manager: FogOfWarManager
var _fog_refresh_timer: float = 0.0


func apply_settings(settings: UnitTrackSettings) -> void:
	_settings = settings


func stop_sampling() -> void:
	_sampling_enabled = false


func is_sampling_enabled() -> bool:
	return _sampling_enabled


func add_movement_sample(
		from_global: Vector2,
		to_global: Vector2,
		settings: UnitTrackSettings = null
	) -> void:
	var segment_settings: UnitTrackSettings = settings if settings != null else _settings
	if from_global.distance_squared_to(to_global) < 0.01:
		return

	var segment := UnitTrackSegmentData.new()
	segment.from_global = from_global
	segment.to_global = to_global
	segment.created_at = _now_sec()
	segment.settings = segment_settings
	segment.fog_visibility = _query_fog_visibility(from_global, to_global)
	segment.color_dirty = true
	_update_segment_draw_color(segment, 0.0)
	_segments.append(segment)

	var cap: int = _settings.max_segments if _settings != null else segment_settings.max_segments
	while _segments.size() > cap:
		_segments.pop_front()

	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var now := _now_sec()
	_fog_refresh_timer -= delta
	var refresh_fog: bool = _fog_refresh_timer <= 0.0
	if refresh_fog:
		_fog_refresh_timer = TRACK_FOG_REFRESH_SEC

	var needs_redraw: bool = refresh_fog
	var i := _segments.size() - 1
	while i >= 0:
		var seg: UnitTrackSegmentData = _segments[i]
		if seg.settings == null:
			_segments.remove_at(i)
			needs_redraw = true
			i -= 1
			continue
		var age: float = now - seg.created_at
		if age >= seg.settings.lifetime_sec:
			_segments.remove_at(i)
			needs_redraw = true
			i -= 1
			continue
		if refresh_fog:
			seg.fog_visibility = _query_fog_visibility(seg.from_global, seg.to_global)
			seg.color_dirty = true
		if _update_segment_draw_color(seg, age):
			needs_redraw = true
		i -= 1

	if not _sampling_enabled and _segments.is_empty():
		queue_free()
		return
	if _segments.is_empty():
		set_process(false)
		queue_redraw()
		return

	if needs_redraw:
		queue_redraw()


func _update_segment_draw_color(seg: UnitTrackSegmentData, age: float) -> bool:
	"""Обновляет cached_draw_color; true если цвет изменился заметно."""
	if seg.settings == null:
		return false
	var fade: float = UnitTrackSettings.fade_factor_for_age(
		age, seg.settings.lifetime_sec, seg.settings.fade_window_sec
	)
	if not seg.color_dirty and absf(fade - seg.cached_fade) < TRACK_FADE_RECALC_EPS:
		return false
	var color: Color = UnitTrackSettings.color_for_fade(
		seg.settings.track_color, seg.settings.dissolve_color, fade
	)
	color.a *= seg.fog_visibility
	seg.cached_fade = fade
	seg.cached_draw_color = color
	seg.color_dirty = false
	return true


func _draw() -> void:
	for seg in _segments:
		if seg.settings == null:
			continue
		if seg.fog_visibility <= 0.01:
			continue
		var color: Color = seg.cached_draw_color
		if color.a <= 0.001:
			continue

		var from_local: Vector2 = to_local(seg.from_global)
		var to_local_pos: Vector2 = to_local(seg.to_global)
		var direction: Vector2 = to_local_pos - from_local
		if direction.length_squared() < 0.01:
			continue
		var offset: Vector2 = direction.orthogonal().normalized() * seg.settings.line_half_spacing
		var width: float = seg.settings.line_width
		draw_line(from_local + offset, to_local_pos + offset, color, width, false)
		draw_line(from_local - offset, to_local_pos - offset, color, width, false)


func _query_fog_visibility(from_global: Vector2, to_global: Vector2) -> float:
	var fog_manager := _find_fog_manager()
	if fog_manager == null:
		return 0.0
	return fog_manager.get_segment_visibility(from_global, to_global)


func _find_fog_manager() -> FogOfWarManager:
	if _fog_manager != null and is_instance_valid(_fog_manager):
		return _fog_manager
	_fog_manager = get_tree().root.find_child("FogOfWarManager", true, false) as FogOfWarManager
	return _fog_manager


func _now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0
