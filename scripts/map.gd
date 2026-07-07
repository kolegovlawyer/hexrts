extends Node2D

func _ready() -> void:
	if Handlers.UIHandler and Handlers.UIHandler.camera:
		Handlers.UIHandler.camera.set_bounds()
	elif Handlers.GameHandler and Handlers.GameHandler.observer_camera:
		Handlers.GameHandler.observer_camera.set_bounds()
