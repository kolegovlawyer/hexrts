class_name UnitSpawner extends Node2D

func _ready():
	Handlers.UnitSpawnHandler = self

func _exit_tree():
	Handlers.UnitSpawnHandler = null

@rpc("any_peer", "reliable")
func spawn_unit(spawn_point, unit_type: String = "base_unit"):
	if is_multiplayer_authority():
		var player_id = multiplayer.get_remote_sender_id()
		
		# Добавляем случайный разброс в пределах 20 пикселей
		var random_offset = Vector2(
			randf_range(-20.0, 20.0),
			randf_range(-20.0, 20.0)
		)
		spawn_point += random_offset
		
		var scene_path := "res://prefabs/units/base_unit.tscn"
		if unit_type == "command_unit":
			scene_path = "res://prefabs/units/command_unit.tscn"
		# TODO: добавить другие типы юнитов по мере расширения
		
		var unit = Handlers.NetworkSpawner.spawn({
			"path": scene_path,
			"resource_info": "null",
			"position": spawn_point,
			"owner_id": player_id
		})
		unit.owner_id = player_id
		print("🏭 СПАВН: Юнит типа '", unit_type, "' создан для игрока ", player_id, " в позиции ", spawn_point)
