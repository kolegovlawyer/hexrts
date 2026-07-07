extends Node2D

@onready var _label: Label = $Label

func set_index(index: int) -> void:
	if _label:
		_label.text = str(index)
