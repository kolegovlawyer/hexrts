extends CanvasLayer

## Overlay FPS / process / physics time (шаг 1 диагностики фризов).
@onready var _label: Label = $Label

func _ready() -> void:
	layer = 100
	if _label:
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _process(_delta: float) -> void:
	if not _label:
		return
	var fps := Engine.get_frames_per_second()
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_label.text = "FPS: %.0f\nProcess: %.2f ms\nPhysics: %.2f ms" % [fps, proc_ms, phys_ms]
