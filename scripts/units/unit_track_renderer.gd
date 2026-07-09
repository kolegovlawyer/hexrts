class_name UnitTrackRenderer
extends Node2D

## Контейнер сегментов следа в мировых координатах.

var _settings: UnitTrackSettings = UnitTrackSettings.new()
var _segments: Array[UnitTrackSegment] = []
var _sampling_enabled: bool = true


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

	var segment := UnitTrackSegment.new()
	add_child(segment)
	segment.setup(from_global, to_global, segment_settings, self)
	_segments.append(segment)

	while _segments.size() > _settings.max_segments:
		var oldest: UnitTrackSegment = _segments.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	set_process(true)


func _process(_delta: float) -> void:
	var i := _segments.size() - 1
	while i >= 0:
		if not is_instance_valid(_segments[i]):
			_segments.remove_at(i)
		i -= 1
	if not _sampling_enabled and _segments.is_empty():
		queue_free()
