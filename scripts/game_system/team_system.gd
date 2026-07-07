class_name TeamSystem extends Node


var players : Array[PlayerProfile] = []
var my_profile : PlayerProfile


### EXPERIMENTAL
var team_count : int = 2

var teams : Array[Team] = []
var TEAM_A : Team
var TEAM_B : Team

func _ready():
	Handlers.TeamHandler = self
	TEAM_A = Team.new()
	TEAM_B = Team.new()
	teams = [TEAM_A, TEAM_B]

func on_connect(team=null):
	if not is_multiplayer_authority():
		var nickname := "Player"
		if Handlers.NetworkHandler and Handlers.NetworkHandler.get("nickname"):
			nickname = str(Handlers.NetworkHandler.nickname)
		rpc_id(1, "request_to_add_to_team", team, nickname)
		rpc_id(1, "request_players_list")
	else:
		# Assume its host | TODO: Make this players not shown in leaderboards
		players.append(PlayerProfile.new().init(GameTypes.ServerPlayerId.TEAM_A, GameTypes.Teams.TEAM_A))
		players.append(PlayerProfile.new().init(GameTypes.ServerPlayerId.TEAM_B, GameTypes.Teams.TEAM_B))
	
func _exit_tree():
	Handlers.TeamHandler = null

@rpc("any_peer", "reliable")
func request_to_add_to_team(team: GameTypes.Teams, nickname: String = ""):
	if is_multiplayer_authority():
		var sender := multiplayer.get_remote_sender_id()
		if Handlers.GameHandler:
			Handlers.GameHandler.on_client_joining(sender, nickname, int(team))
		if not find_player_by_id(sender):
			rpc("add_to_team", sender, team)

@rpc("authority", "reliable", "call_local")
func add_to_team(player, team: GameTypes.Teams): # player is int, PlayerProfile
	# TODO: Update visibility of ally units
	match typeof(player):
		TYPE_INT:
			var new_player = PlayerProfile.new()
			new_player.init(player, team)
			players.append(new_player)
			if not is_multiplayer_authority() and not my_profile:
				if multiplayer.get_unique_id() == new_player.PlayerId:
					my_profile = new_player
		TYPE_OBJECT:
			player.team = team
			players.append(player)
			if not is_multiplayer_authority() and not my_profile:
				if multiplayer.get_unique_id() == player.PlayerId:
					my_profile = player
	var assigned_player_id: int
	if player is int:
		assigned_player_id = player
	else:
		assigned_player_id = player.PlayerId

	var existing_fob = null
	for fob_node in get_tree().get_nodes_in_group("team_%d_fobs" % int(team)):
		if fob_node.owner_id == assigned_player_id:
			existing_fob = fob_node
			break
	if existing_fob == null:
		var team_fobs = get_tree().get_nodes_in_group("team_%d_fobs" % int(team))
		if not team_fobs.is_empty():
			existing_fob = team_fobs.pick_random()
			existing_fob.owner_id = assigned_player_id
	print_rich("[color=green][b][TEAM] Player %s joined to team %s[/b][/color]" % [assigned_player_id, team])

	if is_multiplayer_authority() and Handlers.GameHandler:
		Handlers.GameHandler.on_player_joined_team(assigned_player_id)

	if not is_multiplayer_authority() and multiplayer.get_unique_id() == assigned_player_id:
		call_deferred("_refresh_client_world_visuals")


func _refresh_client_world_visuals() -> void:
	if Handlers.GameHandler and Handlers.GameHandler.has_method("_refresh_client_world_visuals"):
		Handlers.GameHandler._refresh_client_world_visuals()
	else:
		for unit in get_tree().get_nodes_in_group("units"):
			if unit.has_method("update_visual"):
				unit.update_visual()
		for fob_node in get_tree().get_nodes_in_group("fobs"):
			if fob_node.has_method("update_visual"):
				fob_node.update_visual()


@rpc("authority", "reliable", "call_local")
func remove_from_team(player): # player is int, PlayerProfile
	match typeof(player):
		TYPE_INT:
			for num in range(players.size()):
				if players[num].PlayerId == player:
					players.pop_at(num)
					break
		TYPE_OBJECT:
			players.pop_at(players.find(players))
	print_rich("[color=red][b][TEAM] Player %s left the team[/b][/color]" % player)

@rpc("any_peer", "reliable")
func request_players_list():
	if is_multiplayer_authority():
		var ret_players = []
		for player in players:
			ret_players.append(player.deserialize())
		rpc_id(multiplayer.get_remote_sender_id(), "set_players_list", ret_players)

@rpc("authority", "reliable")
func set_players_list(new_players):
	print(new_players)
	for player in new_players:
		players.append(PlayerProfile.new().init(player["PlayerId"], player["Team"]))
	print(players)

func find_player_by_id(player:int):
	for num in range(players.size()):
		if players[num].PlayerId == player:
			return players[num]
	return null

func get_team_players(team: GameTypes.Teams):
	var query_players = []
	for player in players:
		if player.team == team and player.PlayerId != 2 and player.PlayerId != 3: # REWORK!!!
			query_players.append(player)
	return query_players

func get_enemy_team_players(team: GameTypes.Teams):
	var query_players = []
	for player in players:
		if player.team != team and player.PlayerId != 2 and player.PlayerId != 3 and player.team != null: # REWORK!!!
			query_players.append(player)
	return query_players
	
# серверная функция
func get_team(team):
	if team == 0:
		print('TEAM_A')
	elif team == 1:
		print('TEAM_B')

func add_bot_to_team(bot_id: int, team: GameTypes.Teams) -> void:
	"""
	Добавляет бота в систему команд
	Вызывается на сервере при создании бота
	"""
	# Проверяем что бот еще не добавлен
	if find_player_by_id(bot_id):
		print("⚠️ TEAM: Бот ", bot_id, " уже в системе команд")
		return
	
	# Создаем профиль бота и добавляем в команду
	var bot_profile = PlayerProfile.new()
	bot_profile.init(bot_id, team)
	players.append(bot_profile)
	
	print("✅ TEAM: Бот ", bot_id, " добавлен в команду ", team)
	print("  - Всего игроков в системе: ", players.size())
	
	# Выводим список всех игроков для отладки
	print("  - Список игроков:")
	for player in players:
		print("    - ID: ", player.PlayerId, " Team: ", player.team)

func remove_bot_from_team(bot_id: int) -> void:
	"""
	Удаляет бота из системы команд
	"""
	for i in range(players.size()):
		if players[i].PlayerId == bot_id:
			players.pop_at(i)
			print("👋 TEAM: Бот ", bot_id, " удален из системы команд")
			break
