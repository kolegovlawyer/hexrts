class_name UnitTracks
extends Node

## Сэмплинг следов на сервере. Отрисовка — через UnitTrackVisualService (всем клиентам).

@export_group("Sampling")
@export var sample_distance_px: float = 30.0

@export_group("Appearance")
@export var track_color: Color = Color(0.7, 0.7, 0.7, 0.4)
@export var dissolve_color: Color = Color(1.0, 1.0, 1.0, 0.0)
@export var line_width: float = 4.0
@export var line_half_spacing: float = 6.0

@export_group("Lifetime")
@export var lifetime_base_sec: float = 5.0
@export var fade_window_sec: float = 1.5
@export var max_segments: int = 200

@export_group("Cost Scaling")
@export var use_cost_scaling: bool = true
@export var command_width_multiplier: float = 1.4

var _unit: BaseUnit
var _last_sample_pos: Vector2 = Vector2.ZERO
var _has_last_sample: bool = false


func _ready() -> void:
	_unit = get_parent() as BaseUnit
	if _unit == null:
		set_process(false)
		return
	if not _unit.is_multiplayer_authority():
		set_process(false)
		return
	_last_sample_pos = _unit.global_position
	_has_last_sample = true


func _process(_delta: float) -> void:
	if _unit == null or not is_instance_valid(_unit):
		return
	if not _is_leaving_tracks():
		_last_sample_pos = _unit.global_position
		_has_last_sample = true
		return

	var current_pos := _unit.global_position
	if not _has_last_sample:
		_last_sample_pos = current_pos
		_has_last_sample = true
		return

	if current_pos.distance_to(_last_sample_pos) < sample_distance_px:
		return

	_emit_track_sample(_last_sample_pos, current_pos)
	_last_sample_pos = current_pos


func _emit_track_sample(from_pos: Vector2, to_pos: Vector2) -> void:
	if Handlers.UnitTrackVisualHandler == null or _unit.UID == "":
		return
	var settings := _build_settings()
	Handlers.UnitTrackVisualHandler.broadcast_sample(_unit.UID, from_pos, to_pos, settings)


func _exit_tree() -> void:
	if Handlers.UnitTrackVisualHandler != null and _unit != null and _unit.UID != "":
		Handlers.UnitTrackVisualHandler.stop_unit_tracks(_unit.UID)


func refresh_params() -> void:
	pass


func _build_settings() -> UnitTrackSettings:
	var settings := UnitTrackSettings.new()
	settings.sample_distance_px = sample_distance_px
	settings.track_color = track_color
	settings.dissolve_color = dissolve_color
	settings.line_half_spacing = line_half_spacing
	settings.fade_window_sec = fade_window_sec
	settings.max_segments = max_segments

	var scale := 1.0
	if use_cost_scaling and _unit != null:
		var cost := UnitTrackBalance.resolve_cost(_unit)
		scale = UnitPresetBalance.visual_scale_for_cost(cost, _unit.is_command_unit())

	settings.line_width = line_width * scale
	if _unit != null and _unit.is_command_unit():
		settings.line_width *= command_width_multiplier

	if use_cost_scaling:
		settings.lifetime_sec = lifetime_base_sec * scale
	else:
		settings.lifetime_sec = lifetime_base_sec

	return settings


func _is_leaving_tracks() -> bool:
	if _unit.unit_state == BaseUnit.UNIT_STATES.MOVING:
		return true
	var body := _unit as CharacterBody2D
	if body != null:
		return body.velocity.length_squared() > 64.0
	return false
