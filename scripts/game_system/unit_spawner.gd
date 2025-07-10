class_name UnitSpawner extends Node2D

func _ready():
	Handlers.UnitSpawnHandler = self

func _exit_tree():
	Handlers.UnitSpawnHandler = null

@rpc("any_peer", "reliable")
func spawn_unit(spawn_point): # ADD UNIT RESOURCE PARAMETER
	if is_multiplayer_authority():
		var player = Handlers.TeamHandler.find_player_by_id(multiplayer.get_remote_sender_id())
		spawn_point += Vector2(50,50)
		#if player.Team == GameTypes.Teams.TEAM_A:
			#unit_position = Handlers.UnitSelectionHandler.selected_fob.position
			##$TeamA/Ground/GroundSpawn1/SpawnPoint/DebugMesh.global_position # Do it another way
			##unit.nav_agent.target_position = $TeamA/Ground/GroundSpawn1/TargetPoint.global_position <- Добавить выезжание
		#elif player.Team == GameTypes.Teams.TEAM_B:
			#unit_position = Handlers.UnitSelectionHandler.selected_fob.position
			##unit.nav_agent.target_position = $TeamB/Ground/GroundSpawn1/TargetPoint.global_position <- Добавить выезжание
		var player_id = multiplayer.get_remote_sender_id()
		var unit : BaseUnit = Handlers.NetworkSpawner.spawn({"path":"res://prefabs/units/base_unit.tscn", "resource_info":"null","position":spawn_point, "owner_id":player_id}) #"owner_id":player_id
		print("ID is ", multiplayer.get_remote_sender_id())
		unit.owner_id = multiplayer.get_remote_sender_id()
