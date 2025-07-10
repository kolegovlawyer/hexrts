extends Node2D

func _ready() -> void:
	if not is_multiplayer_authority():
		Handlers.UIHandler.camera.set_bounds()
