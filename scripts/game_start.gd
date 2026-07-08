class_name GameManager extends Node

const _BattleLogServiceScript := preload("res://scripts/game_system/battle_log_service.gd")
const _HexCoordinatesScript := preload("res://scripts/game_system/hex_coordinates.gd")

var game_type = "UNKNOWN"
var map
@onready var units_dict: Dictionary[String, BaseUnit] = {}
var fobs_dict: Dictionary = {}

# Словарь гексов карты: позиция_гекса -> объект Hex
var hexes_dict: Dictionary = {}

# Ссылка на OverlayMap для обновления тайлов захвата
var overlay_map: TileMapLayer

# Камера наблюдения в режиме dedicated server (без клиентского HUD)
var observer_camera: Camera2D = null

### BOT MANAGEMENT SYSTEM ###

# Список активных ботов
var active_bots: Array[Bot] = []

### POINTS SYSTEM ###

const UNIT_SPAWN_COST: int = 10

var match_duration_preset: int = VictoryBalance.DurationPreset.NORMAL
var active_balance: Dictionary = {}

var game_ended: bool = false
var match_elapsed_seconds: float = 0.0

# Очки игроков: player_id -> {recruitment_points, victory_points, points_revision}
var player_points: Dictionary = {}

# peer_id -> nickname (normalized key)
var _player_nicknames: Dictionary = {}
# nickname -> {points, team, old_peer_id} — сохранённая сессия после дисконнекта
var _disconnected_sessions: Dictionary = {}

# Таймер для обновления очков каждую секунду
var points_timer: Timer

var battle_log: Node = null

# player_id -> включена ли атака на ходу (HUD ToggleMovementAttack)
var movement_attack_by_player: Dictionary = {}


# Called when the node enters the scene tree for the first time.
func _ready():
	set_multiplayer_authority(1)
	Handlers.GameHandler = self
	
	# Инициализируем систему очков только на сервере
	if is_multiplayer_authority():
		setup_points_system()
		battle_log = _BattleLogServiceScript.new()
		battle_log.name = "BattleLogService"
		add_child(battle_log)
		battle_log.setup(self)
		
		# Добавляем систему диагностики
		var debug_system = preload("res://scripts/debug_system.gd").new()
		add_child(debug_system)

# Delete handler on scene exit
func _exit_tree():
	Handlers.GameHandler = null

### POINTS SYSTEM FUNCTIONS ###

func set_match_duration_preset(preset_id: int) -> void:
	match_duration_preset = preset_id


func setup_points_system() -> void:
	Handlers.dprint("🏆 POINTS: Инициализация системы очков на сервере")

	points_timer = Timer.new()
	points_timer.wait_time = 1.0
	points_timer.timeout.connect(_on_points_timer_timeout)
	points_timer.autostart = true
	add_child(points_timer)

	for player_id in multiplayer.get_peers():
		_initialize_player_points(player_id)
		movement_attack_by_player[player_id] = true

	# Хост (peer 1) играет на сервере, но не входит в get_peers()
	_initialize_player_points(1)
	movement_attack_by_player[1] = true

	var server_id := multiplayer.get_unique_id()
	if server_id != 1:
		_initialize_player_points(server_id)
		movement_attack_by_player[server_id] = true

	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)


func _initialize_active_balance() -> void:
	if not is_multiplayer_authority():
		return

	var hex_count := hexes_dict.size()
	var map_name := str(map) if map else "test_world_1"
	active_balance = VictoryBalance.build_active_balance(hex_count, map_name, match_duration_preset)
	match_elapsed_seconds = 0.0
	game_ended = false

	Handlers.dprint("⚖️ BALANCE: Карта=", map_name, " гексы=", hex_count)
	Handlers.dprint("  - VP to win: ", active_balance["victory_points_to_win"])
	Handlers.dprint("  - Match duration: ", active_balance["match_duration_minutes"], " min")
	Handlers.dprint("  - Domination: ", active_balance["domination_hexes"], " hexes")

	_broadcast_match_balance()

	for player_id in player_points.keys():
		if not _is_player_bot(player_id):
			_sync_points_for_player(player_id, false)


func _broadcast_match_balance() -> void:
	if active_balance.is_empty():
		return

	for player_id in player_points.keys():
		if _is_player_bot(player_id):
			continue
		_send_match_balance_to_player(player_id)


func _send_match_balance_to_player(player_id: int) -> void:
	if _is_local_human_player(player_id):
		if Handlers.UIHandler:
			Handlers.UIHandler.init_match_balance(active_balance)
	elif _is_connected_remote_peer(player_id):
		sync_match_balance.rpc_id(player_id, active_balance)


func _initialize_player_points(player_id: int) -> void:
	Handlers.dprint("🎯 GAME DEBUG: Инициализация очков для player_id: ", player_id)

	player_points[player_id] = {
		"recruitment_points": VictoryBalance.INITIAL_RECRUITMENT_POINTS,
		"victory_points": 0.0,
		"points_revision": 0,
	}

	if _is_player_bot(player_id):
		Handlers.dprint("🤖 GAME DEBUG: Игрок ", player_id, " определен как бот")

	_sync_points_for_player(player_id, false)


func _on_player_connected(_player_id: int) -> void:
	# Вход игрока обрабатывается в on_client_joining через request_to_add_to_team
	pass


func on_client_joining(peer_id: int, nickname: String, _team: int) -> void:
	if not is_multiplayer_authority():
		return

	var nick_key := _normalize_nickname(nickname, peer_id)
	_player_nicknames[peer_id] = nick_key

	if _disconnected_sessions.has(nick_key):
		var saved: Dictionary = _disconnected_sessions[nick_key]
		player_points[peer_id] = saved["points"].duplicate(true)
		var old_peer_id: int = int(saved.get("old_peer_id", -1))
		if old_peer_id > 0 and old_peer_id != peer_id:
			_reassign_owned_entities(old_peer_id, peer_id)
		_disconnected_sessions.erase(nick_key)
		Handlers.dprint("🔄 RECONNECT: Восстановлена сессия ", nick_key, " для peer ", peer_id)
	else:
		_initialize_player_points(peer_id)

	movement_attack_by_player[peer_id] = true
	_sync_points_for_player(peer_id, false)
	if not active_balance.is_empty():
		_send_match_balance_to_player(peer_id)


func _normalize_nickname(nickname: String, peer_id: int) -> String:
	var trimmed := nickname.strip_edges().to_lower()
	if trimmed == "":
		return "player_%d" % peer_id
	return trimmed


func _save_disconnected_session(player_id: int) -> void:
	var nick_key: String = str(_player_nicknames.get(player_id, ""))
	if nick_key == "" or not player_points.has(player_id):
		return
	_disconnected_sessions[nick_key] = {
		"points": player_points[player_id].duplicate(true),
		"team": _get_player_team(player_id),
		"old_peer_id": player_id,
	}
	Handlers.dprint("💾 RECONNECT: Сохранена сессия ", nick_key, " (peer ", player_id, ")")


func _reassign_owned_entities(old_id: int, new_id: int) -> void:
	for fob_node in get_tree().get_nodes_in_group("fobs"):
		if fob_node.owner_id == old_id:
			if fob_node.has_method("server_reassign_owner"):
				fob_node.server_reassign_owner(old_id, new_id)
			else:
				fob_node.owner_id = new_id
	for unit in get_tree().get_nodes_in_group("units"):
		if unit is BaseUnitServer and unit.owner_id == old_id:
			unit.server_reassign_owner(new_id)


func on_player_joined_team(peer_id: int) -> void:
	if not is_multiplayer_authority():
		return

	for unit in get_tree().get_nodes_in_group("units"):
		if unit is BaseUnitServer:
			unit.force_update_visibility()

	for fob_node in get_tree().get_nodes_in_group("fobs"):
		if fob_node.owner_id == peer_id and fob_node.has_method("sync_spawn_ui_for_owner"):
			fob_node.sync_spawn_ui_for_owner()

	if _is_local_human_player(peer_id):
		call_deferred("_refresh_client_world_visuals")
	elif _is_connected_remote_peer(peer_id):
		notify_reconnect_visual_refresh.rpc_id(peer_id)


@rpc("any_peer", "reliable")
func notify_reconnect_visual_refresh() -> void:
	if multiplayer.is_server():
		return
	_refresh_client_world_visuals()


func _refresh_client_world_visuals() -> void:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.has_method("update_visual"):
			unit.update_visual()
	for fob_node in get_tree().get_nodes_in_group("fobs"):
		if fob_node.has_method("update_visual"):
			fob_node.update_visual()


func _on_player_disconnected(player_id: int) -> void:
	_save_disconnected_session(player_id)
	_player_nicknames.erase(player_id)
	if player_points.has(player_id):
		player_points.erase(player_id)
	Handlers.dprint("👋 POINTS: Игрок ", player_id, " отключён (сессия сохранена для reconnect)")


func _on_points_timer_timeout() -> void:
	if game_ended:
		return

	match_elapsed_seconds += 1.0

	for player_id in player_points.keys():
		_update_player_points(player_id)

	if _check_time_limit_victory():
		return

	_check_domination_victory()


func _update_player_points(player_id: int) -> void:
	if not player_points.has(player_id):
		return

	var player_hexes_count := _count_player_hexes(player_id)
	var recruitment_gain := VictoryBalance.calculate_recruitment_gain(player_hexes_count)
	var victory_gain := VictoryBalance.calculate_victory_gain(player_hexes_count)

	player_points[player_id]["recruitment_points"] += recruitment_gain
	player_points[player_id]["victory_points"] += victory_gain

	_sync_points_for_player(player_id, true)

	if _check_vp_threshold_victory(player_id):
		return

	var is_bot := _is_player_bot(player_id)
	if is_bot or int(match_elapsed_seconds) % 10 == 0:
		Handlers.dprint(
			"📊 POINTS: Игрок ", player_id,
			" гексы: ", player_hexes_count,
			" найм: +", recruitment_gain,
			" VP: +", victory_gain
		)


func _get_enemy_team_victory_points(player_id: int) -> float:
	var team := _get_player_team(player_id)
	if team == -1 or not Handlers.TeamHandler:
		return 0.0
	var max_vp := 0.0
	for enemy in Handlers.TeamHandler.get_enemy_team_players(team):
		var enemy_id: int = enemy.PlayerId
		if player_points.has(enemy_id):
			max_vp = maxf(max_vp, float(player_points[enemy_id]["victory_points"]))
	return max_vp


func _is_connected_remote_peer(peer_id: int) -> bool:
	return peer_id in multiplayer.get_peers()


func _sync_points_for_player(player_id: int, increment_revision: bool = false) -> void:
	if not multiplayer.is_server():
		return
	if not player_points.has(player_id) or _is_player_bot(player_id):
		return

	if increment_revision:
		player_points[player_id]["points_revision"] = int(player_points[player_id].get("points_revision", 0)) + 1

	var recruitment: float = player_points[player_id]["recruitment_points"]
	var victory: float = player_points[player_id]["victory_points"]
	var enemy_victory: float = _get_enemy_team_victory_points(player_id)
	var revision: int = player_points[player_id]["points_revision"]
	var victory_max: int = int(active_balance.get("victory_points_to_win", 1000))

	if _is_local_human_player(player_id):
		if Handlers.UIHandler:
			Handlers.UIHandler.update_points_display(
				recruitment, victory, revision, victory_max, enemy_victory
			)
	elif _is_connected_remote_peer(player_id):
		sync_player_points.rpc_id(
			player_id, recruitment, victory, revision, victory_max, enemy_victory
		)


func _is_local_human_player(player_id: int) -> bool:
	return multiplayer.get_unique_id() == player_id and not _is_player_bot(player_id)


func _count_player_hexes(player_id: int) -> int:
	var player_team := _get_player_team(player_id)
	if player_team == -1:
		return 0
	return _count_team_hexes(player_team)


func _count_team_hexes(team: int) -> int:
	var count := 0
	for hex in hexes_dict.values():
		if hex.team_owner == team:
			count += 1
	return count


func _get_player_team(player_id: int) -> int:
	if not Handlers.TeamHandler:
		return -1

	if _is_player_bot(player_id):
		for bot in active_bots:
			if bot.bot_id == player_id:
				return int(bot.bot_team)
		return -1

	var player = Handlers.TeamHandler.find_player_by_id(player_id)
	if not player:
		return -1
	return int(player.team)


func _get_human_players_on_team(team: int) -> Array[int]:
	var result: Array[int] = []
	if not Handlers.TeamHandler:
		return result
	for player in Handlers.TeamHandler.players:
		if int(player.team) != team:
			continue
		if _is_player_bot(player.PlayerId):
			continue
		if player.PlayerId == 2 or player.PlayerId == 3:
			continue
		result.append(player.PlayerId)
	return result


func _get_enemy_human_player_ids(player_id: int) -> Array[int]:
	var team := _get_player_team(player_id)
	if team == -1 or not Handlers.TeamHandler:
		return []
	var result: Array[int] = []
	for enemy in Handlers.TeamHandler.get_enemy_team_players(team):
		if _is_player_bot(enemy.PlayerId):
			continue
		result.append(enemy.PlayerId)
	return result


func _check_vp_threshold_victory(player_id: int) -> bool:
	if game_ended or active_balance.is_empty():
		return false
	var threshold: int = int(active_balance["victory_points_to_win"])
	if player_points[player_id]["victory_points"] >= threshold:
		end_match(
			[player_id],
			_get_enemy_human_player_ids(player_id),
			VictoryBalance.REASON_VP_THRESHOLD
		)
		return true
	return false


func _check_domination_victory() -> bool:
	if game_ended or active_balance.is_empty():
		return false

	var threshold: int = int(active_balance["domination_hexes"])
	for team in [0, 1]:
		if _count_team_hexes(team) >= threshold:
			var winners := _get_human_players_on_team(team)
			var losers := _get_human_players_on_team(1 - team)
			end_match(winners, losers, VictoryBalance.REASON_DOMINATION)
			return true
	return false


func _check_time_limit_victory() -> bool:
	if game_ended or active_balance.is_empty():
		return false

	if match_elapsed_seconds < float(active_balance["match_duration_seconds"]):
		return false

	var best_vp := -1.0
	var best_players: Array[int] = []

	for player_id in player_points.keys():
		if _is_player_bot(player_id):
			continue
		var vp: float = player_points[player_id]["victory_points"]
		if vp > best_vp:
			best_vp = vp
			best_players = [player_id]
		elif is_equal_approx(vp, best_vp) and player_id not in best_players:
			best_players.append(player_id)

	if best_players.is_empty():
		return false

	if best_players.size() > 1:
		end_match_draw(best_players, VictoryBalance.REASON_TIME_LIMIT)
	else:
		var winner_id: int = best_players[0]
		end_match([winner_id], _get_enemy_human_player_ids(winner_id), VictoryBalance.REASON_TIME_LIMIT)
	return true


func end_match(winner_player_ids: Array[int], loser_player_ids: Array[int], reason: String) -> void:
	if game_ended:
		return
	game_ended = true
	if points_timer:
		points_timer.stop()

	Handlers.dprint("🏁 MATCH END: ", reason, " winners=", winner_player_ids, " losers=", loser_player_ids)

	for winner_id in winner_player_ids:
		_notify_match_result(winner_id, true, reason)
	for loser_id in loser_player_ids:
		if loser_id not in winner_player_ids:
			_notify_match_result(loser_id, false, reason)


func end_match_draw(player_ids: Array[int], reason: String) -> void:
	if game_ended:
		return
	game_ended = true
	if points_timer:
		points_timer.stop()

	Handlers.dprint("🏁 MATCH END (DRAW): ", reason, " players=", player_ids)
	for player_id in player_ids:
		_notify_match_result(player_id, false, reason, true)


func _notify_match_result(player_id: int, is_winner: bool, reason: String, is_draw: bool = false) -> void:
	if _is_player_bot(player_id):
		return
	if _is_local_human_player(player_id):
		_show_game_over_local(is_winner, reason, is_draw)
	elif _is_connected_remote_peer(player_id):
		show_game_over.rpc_id(player_id, is_winner, reason, is_draw)


func _show_game_over_local(is_winner: bool, reason: String, is_draw: bool) -> void:
	if not Handlers.UIHandler:
		return
	Handlers.UIHandler.show_game_over(is_winner, reason, is_draw)


@rpc("any_peer", "reliable")
func sync_match_balance(balance: Dictionary) -> void:
	if multiplayer.is_server():
		return
	if Handlers.UIHandler:
		Handlers.UIHandler.init_match_balance(balance)


@rpc("any_peer", "reliable")
func sync_player_points(
		recruitment_points: float,
		victory_points: float,
		revision: int,
		victory_max: int,
		enemy_victory_points: float = 0.0
	) -> void:
	if multiplayer.is_server():
		return
	if Handlers.UIHandler:
		Handlers.UIHandler.update_points_display(
			recruitment_points, victory_points, revision, victory_max, enemy_victory_points
		)


@rpc("any_peer", "reliable")
func show_game_over(is_winner: bool, reason: String, is_draw: bool) -> void:
	if multiplayer.is_server():
		return
	if Handlers.UIHandler:
		Handlers.UIHandler.show_game_over(is_winner, reason, is_draw)


@rpc("authority", "call_remote", "reliable")
func rpc_battle_log_event(
		event_type: int,
		hex_tile: Vector2i,
		match_seconds: float,
		actor_name: String = ""
	) -> void:
	if Handlers.UIHandler:
		Handlers.UIHandler.append_battle_log_event(
			event_type, hex_tile, match_seconds, actor_name
		)


@rpc("authority", "call_remote", "reliable")
func deliver_unit_vitals(
		unit_uid: String,
		health_value: int,
		shield_value: int,
		max_health_value: int,
		max_shield_value: int
	) -> void:
	if multiplayer.is_server():
		return
	_deliver_unit_vitals_local(
		unit_uid, health_value, shield_value, max_health_value, max_shield_value
	)


func _deliver_unit_vitals_local(
		unit_uid: String,
		health_value: int,
		shield_value: int,
		max_health_value: int,
		max_shield_value: int
	) -> void:
	for node in get_tree().get_nodes_in_group("units"):
		if not node is BaseUnit:
			continue
		var unit := node as BaseUnit
		if unit.UID != unit_uid:
			continue
		if unit.has_method("apply_vitals_from_network"):
			unit.apply_vitals_from_network(
				health_value, shield_value, max_health_value, max_shield_value
			)
		return

func register_fob(fob_node: fob) -> void:
	if not is_multiplayer_authority() or fob_node.UID == "":
		return
	fobs_dict[fob_node.UID] = fob_node

func unregister_fob(fob_node: fob) -> void:
	if fob_node.UID in fobs_dict:
		fobs_dict.erase(fob_node.UID)

func handle_fob_destroyed(owner_player_id: int) -> void:
	if not is_multiplayer_authority() or game_ended:
		return
	Handlers.dprint("🏚️ FOB: База игрока ", owner_player_id, " уничтожена")
	var winners := _get_enemy_human_player_ids(owner_player_id)
	end_match(winners, [owner_player_id], VictoryBalance.REASON_FOB_DESTROYED)

### SPAWN VALIDATION SYSTEM ###

func validate_unit_spawn(player_id: int, unit_cost: int = UNIT_SPAWN_COST) -> bool:
	"""
	Проверяет, может ли игрок заспавнить юнита
	Вызывается перед добавлением в очередь отложенного спавна
	"""
	Handlers.dprint("🔍 GAME DEBUG: validate_unit_spawn для player_id: ", player_id, " cost: ", unit_cost)
	Handlers.dprint("  - player_points keys: ", player_points.keys())
	
	if not player_points.has(player_id):
		Handlers.dprint("❌ SPAWN: Игрок ", player_id, " не найден в системе очков")
		return false
	
	var current_points = player_points[player_id]["recruitment_points"]
	Handlers.dprint("💰 GAME DEBUG: Текущие очки игрока ", player_id, ": ", current_points)
	
	if current_points < unit_cost:
		Handlers.dprint("❌ SPAWN: У игрока ", player_id, " недостаточно очков (", current_points, "/", unit_cost, ")")
		return false
	
	# Списываем очки
	player_points[player_id]["recruitment_points"] -= unit_cost
	Handlers.dprint("✅ SPAWN: Списано ", unit_cost, " очков у игрока ", player_id, " (осталось: ", player_points[player_id]["recruitment_points"], ")")

	_sync_points_for_player(player_id, true)

	return true

# Удалено: add_delayed_spawn, _process_delayed_spawn_queue, _execute_delayed_spawn

func instantiate_network():
	if game_type.to_lower() == "server":
		add_child(load("res://scenes/server/server.tscn").instantiate())
	else:
		add_child(load("res://scenes/client/client.tscn").instantiate())

func set_map(map_name: String) -> void:
	map = map_name
	var scene_path := VictoryBalance.resolve_map_scene_path(map_name)
	var map_obj = load(scene_path).instantiate()
	for map_node in get_node("Map").get_children():
		map_node.queue_free()
	get_node("Map").add_child(map_obj)

	if Handlers.UIHandler:
		Handlers.UIHandler.bind_map_world()

	call_deferred("initialize_hexes")

func create_camera(role: String) -> void:
	var camera_node: Camera2D = load("res://scenes/client/camera_2d.tscn").instantiate()
	add_child(camera_node)
	if role == "Server":
		observer_camera = camera_node
		if camera_node.has_method("set_observer_mode"):
			camera_node.set_observer_mode(true)
	elif role == "Client" and Handlers.UIHandler:
		Handlers.UIHandler.camera = camera_node


func setup_observer_camera_bounds() -> void:
	if observer_camera and observer_camera.has_method("set_bounds"):
		observer_camera.set_bounds()

func create_ui():
	var ui = load("res://scenes/client/base_ui.tscn").instantiate()
	$"%UICanvasLayer".add_child(ui)

func set_type_server(port: int) -> void:
	game_type = "Server"

	instantiate_network()
	create_camera(game_type)

	Handlers.NetworkHandler.start_server(port)

func set_type_client(host:String, port:int, nickname:String):
	game_type = "Client"
	
	instantiate_network()
	create_ui()
	create_camera(game_type)
	
	Handlers.NetworkHandler.start_client(host, port, nickname)


	
### UNIT FUNCTIONS ###


func get_unit_by_name(node_name):
	return get_node("Spawnables").get_node_or_null(str(node_name))
	
func get_all_units():
	return get_node("Spawnables").get_children()

### BOT MANAGEMENT FUNCTIONS ###

func _is_player_bot(player_id: int) -> bool:
	"""
	Проверяет является ли игрок ботом
	"""
	for bot in active_bots:
		if bot.bot_id == player_id:
			return true
	return false

func get_bot_team_by_id(player_id: int) -> int:
	if active_bots.is_empty():
		return -1
	for bot in active_bots:
		if bot.bot_id == player_id:
			return int(bot.bot_team)
	return -1


@rpc("any_peer", "reliable")
func set_movement_attack_enabled(enabled: bool) -> void:
	if not is_multiplayer_authority():
		return
	var player_id: int = multiplayer.get_remote_sender_id()
	if player_id == 0:
		player_id = multiplayer.get_unique_id()
	movement_attack_by_player[player_id] = enabled


func is_movement_attack_enabled(player_id: int) -> bool:
	if get_bot_team_by_id(player_id) != -1:
		return false
	return movement_attack_by_player.get(player_id, true)


func register_bot(bot: Bot) -> void:
	"""
	Регистрирует бота в системе управления
	"""
	Handlers.dprint("📋 GAME DEBUG: Попытка регистрации бота:")
	Handlers.dprint("  - bot_name: ", bot.bot_name if bot.bot_name else "не задано")
	Handlers.dprint("  - bot_id: ", bot.bot_id)
	Handlers.dprint("  - bot_team: ", bot.bot_team)
	Handlers.dprint("  - активных ботов до: ", active_bots.size())
	
	if bot not in active_bots:
		active_bots.append(bot)
		Handlers.dprint("🤖 GAME: Зарегистрирован бот ", bot.bot_name, " (всего ботов: ", active_bots.size(), ")")
		
		# Убеждаемся что у бота есть очки в системе
		if not player_points.has(bot.bot_id):
			Handlers.dprint("💰 GAME DEBUG: Инициализируем очки для нового бота ", bot.bot_id)
			_initialize_player_points(bot.bot_id)
		
		# Подключаем существующие юниты к новому боту
		_connect_existing_units_to_bot(bot)
	else:
		Handlers.dprint("⚠️ GAME DEBUG: Бот уже зарегистрирован")

func unregister_bot(bot: Bot) -> void:
	"""
	Удаляет бота из системы управления
	"""
	if bot in active_bots:
		active_bots.erase(bot)
		
		# Удаляем бота из системы команд
		if Handlers.TeamHandler:
			Handlers.TeamHandler.remove_bot_from_team(bot.bot_id)
		
		Handlers.dprint("👋 GAME: Бот ", bot.bot_name, " удален из системы")

func _connect_existing_units_to_bot(bot: Bot) -> void:
	"""
	Подключает уже существующих юнитов к новому боту
	"""
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if unit is BaseUnit:
			_connect_unit_signals_to_bots(unit)

func _connect_unit_signals_to_bots(unit: BaseUnit) -> void:
	"""
	Подключает сигналы юнита ко всем активным ботам
	"""
	Handlers.dprint("📡 GAME: Подключение сигналов юнита ", unit.name, " к ботам (", active_bots.size(), " ботов)")
	
	for bot in active_bots:
		Handlers.dprint("  - Подключение к боту ", bot.bot_name)
		
		if unit is BaseUnitServer:
			var server_unit := unit as BaseUnitServer
			if not server_unit.under_attack.is_connected(bot._on_unit_under_attack):
				server_unit.under_attack.connect(bot._on_unit_under_attack)
				Handlers.dprint("    ✅ Подключен сигнал under_attack")
			
			if not server_unit.attack_started.is_connected(bot._on_attack_started):
				server_unit.attack_started.connect(bot._on_attack_started)
				Handlers.dprint("    ✅ Подключен сигнал attack_started")
		
		if not unit.unit_died.is_connected(bot._on_unit_died):
			unit.unit_died.connect(bot._on_unit_died)
			Handlers.dprint("    ✅ Подключен сигнал unit_died")

func _on_new_unit_spawned(unit: BaseUnit) -> void:
	"""
	Вызывается при спавне нового юнита для подключения к ботам
	"""
	if is_multiplayer_authority():
		Handlers.dprint("🎯 GAME: Новый юнит заспавнен: ", unit.name, " owner_id: ", unit.owner_id)
		_connect_unit_signals_to_bots(unit)

func register_new_unit(unit: BaseUnit) -> void:
	"""
	Регистрирует новый юнит в системе и подключает к ботам
	Вызывается из _ready() юнита на сервере
	"""
	if is_multiplayer_authority():
		_on_new_unit_spawned(unit)

### HEX CAPTURE SYSTEM ###

func initialize_hexes() -> void:
	"""
	Инициализирует словарь гексов на основе MainMap (где определены позиции)
	OverlayMap используется только для отображения статуса захвата
	Вызывается и на сервере, и на клиентах
	"""
	var server_or_client = "СЕРВЕР" if is_multiplayer_authority() else "КЛИЕНТ"
	Handlers.dprint("🔧 DEBUG: initialize_hexes вызвана на ", server_or_client)
	
	var map_node = get_node("Map").get_child(0) # test_world_1
	Handlers.dprint("🔧 DEBUG: map_node найден: ", map_node)
	
	# Ищем MainMap для получения позиций гексов
	var main_map = map_node.get_node("MainMap")
	if not main_map:
		Handlers.dprint("⚠️ ГЕКСЫ: MainMap не найден!")
		return
	else:
		Handlers.dprint("✅ DEBUG: MainMap найден: ", main_map)
	
	# Ищем OverlayMap для управления визуалом
	overlay_map = map_node.get_node("OverlayMap")
	if not overlay_map:
		Handlers.dprint("⚠️ ГЕКСЫ: OverlayMap не найден!")
		return
	else:
		Handlers.dprint("✅ DEBUG: OverlayMap найден: ", overlay_map)
		Handlers.dprint("📍 DEBUG: OverlayMap position: ", overlay_map.position)
	
	# Получаем все используемые ячейки из MainMap (фактические позиции гексов)
	var used_cells = main_map.get_used_cells()
	Handlers.dprint("📊 DEBUG: Найдено гексов в MainMap: ", used_cells.size())
	hexes_dict.clear()
	
	for cell_pos in used_cells:
		# Проверяем есть ли соответствующий тайл в OverlayMap для определения статуса
		var overlay_atlas_coords = overlay_map.get_cell_atlas_coords(cell_pos)
		var initial_team = -1  # По умолчанию нейтральный
		
		#Handlers.dprint("🎨 DEBUG: Гекс ", cell_pos, " OverlayMap atlas_coords: ", overlay_atlas_coords)
		
		# Определяем команду по atlas координатам OverlayMap
		# (0,0) - команда A (0), (1,0) - команда B (1), (2,0) - нейтральный (-1)
		match overlay_atlas_coords:
			Vector2i(0, 0): initial_team = 0  # Команда A
			Vector2i(1, 0): initial_team = 1  # Команда B  
			Vector2i(2, 0): initial_team = -1 # Нейтральный
			Vector2i(-1, -1): initial_team = -1 # Нет тайла в OverlayMap = нейтральный
			_: initial_team = -1
		
		# Создаем объект гекса
		var hex = preload("res://scripts/singletons/hex.gd").new(cell_pos, initial_team)
		hexes_dict[cell_pos] = hex
		#Handlers.dprint("🎯 DEBUG: Создан гекс ", cell_pos, " команда ", initial_team)
	
	Handlers.dprint("🗺️ ГЕКСЫ: Инициализировано ", hexes_dict.size(), " гексов на ", server_or_client)
	if hexes_dict.size() <= 20:  # Показываем список только если гексов немного
		Handlers.dprint("📋 DEBUG: Список всех гексов:")
		for pos in hexes_dict.keys():
			var team_str = ""
			match hexes_dict[pos].team_owner:
				0: team_str = "A"
				1: team_str = "B"
				-1: team_str = "нейтральный"
				_: team_str = str(hexes_dict[pos].team_owner)
			Handlers.dprint("  - Гекс ", pos, " команда ", team_str, " (", hexes_dict[pos].team_owner, ")")
	else:
		Handlers.dprint("📊 DEBUG: Слишком много гексов для детального отображения (", hexes_dict.size(), ")")

	if is_multiplayer_authority():
		_initialize_active_balance()
		setup_observer_camera_bounds()

	_HexCoordinatesScript.initialize_from_tile_bounds(used_cells)
	_setup_hex_coordinate_labels()

	_try_autoload_unit_presets()


func _setup_hex_coordinate_labels() -> void:
	var map_root := get_node_or_null("Map")
	if map_root == null or map_root.get_child_count() == 0:
		return
	var map_node: Node = map_root.get_child(0)
	var label_layer: Node = map_node.get_node_or_null("HexLabelLayer")
	if label_layer == null or not label_layer.has_method("build_labels"):
		return
	if overlay_map == null:
		return
	label_layer.build_labels(overlay_map)


func _try_autoload_unit_presets() -> void:
	if UnitPresetManager.try_autoload_presets():
		Handlers.dprint("UnitPresetManager: пресеты загружены с диска")

func get_hex_at_position(hex_position: Vector2i):
	"""Возвращает объект гекса по позиции или null если гекса нет"""
	var hex = hexes_dict.get(hex_position, null)
	
	if not hex:
		Handlers.dprint("❌ DEBUG: Гекс с координатами ", hex_position, " не найден!")
		Handlers.dprint("🔍 DEBUG: Ближайшие гексы:")
		for pos in hexes_dict.keys():
			var distance = hex_position.distance_to(pos)
			if distance <= 3:  # Показываем гексы в радиусе 3 тайлов
				Handlers.dprint("  - ", pos, " (расстояние: ", distance, ")")
	
	return hex

func update_hex_overlay(hex_position: Vector2i, team_owner: int) -> void:
	"""
	Обновляет тайл в OverlayMap на СЕРВЕРЕ и отправляет RPC клиентам
	Вызывается только на сервере при захвате гекса
	"""
	if not is_multiplayer_authority():
		Handlers.dprint("⚠️ ГЕКСЫ: update_hex_overlay должна вызываться только на сервере!")
		return
		
	if not overlay_map:
		Handlers.dprint("⚠️ ГЕКСЫ: OverlayMap не найден для обновления!")
		return
	
	Handlers.dprint("🔧 DEBUG: update_hex_overlay (СЕРВЕР) для гекса ", hex_position, " команда ", team_owner)
	
	# Обновляем серверную OverlayMap
	_update_overlay_visual(hex_position, team_owner, team_owner)
	
	# Отправляем RPC всем клиентам о захвате гекса
	sync_hex_capture.rpc(hex_position, team_owner)
	
	var team_str = ""
	match team_owner:
		0: team_str = "A"
		1: team_str = "B"
		-1: team_str = "нейтральный"
		_: team_str = str(team_owner)
	Handlers.dprint("📡 ГЕКСЫ: RPC отправлен всем клиентам о захвате гекса ", hex_position, " командой ", team_str)

	_check_domination_victory()

@rpc("authority", "call_remote", "reliable")
func sync_hex_capture(hex_position: Vector2i, new_owner_team: int) -> void:
	"""
	RPC функция для синхронизации захвата гекса на клиентах
	Каждый клиент обновляет визуал в зависимости от своей команды
	"""
	if is_multiplayer_authority():
		Handlers.dprint("⚠️ ГЕКСЫ: sync_hex_capture не должна вызываться на сервере!")
		return
	
	Handlers.dprint("📨 КЛИЕНТ: Получен RPC о захвате гекса ", hex_position, " командой ", new_owner_team)
	
	# Обновляем объект гекса в локальном словаре
	var hex = get_hex_at_position(hex_position)
	if hex:
		hex.team_owner = new_owner_team
		Handlers.dprint("✅ КЛИЕНТ: Обновлен локальный объект гекса ", hex_position)
	
	# Определяем как отображать гекс с точки зрения этого клиента
	var my_team = -1
	if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
		my_team = Handlers.TeamHandler.my_profile.team
		Handlers.dprint("👤 КЛИЕНТ: Моя команда = ", my_team)
	else:
		Handlers.dprint("❌ КЛИЕНТ: TeamHandler или my_profile не найден!")
	
	# Обновляем визуал OverlayMap для клиента
	_update_overlay_visual(hex_position, new_owner_team, my_team)

func _update_overlay_visual(hex_position: Vector2i, hex_owner_team: int, viewer_team: int) -> void:
	"""
	Внутренняя функция для обновления визуала OverlayMap
	hex_owner_team - кому принадлежит гекс
	viewer_team - кто смотрит (для определения союзник/враг)
	"""
	if not overlay_map:
		Handlers.dprint("⚠️ ГЕКСЫ: OverlayMap не найден!")
		return
	
	var atlas_coords = Vector2i(2, 0)  # По умолчанию нейтральный
	
	# Определяем atlas координаты с точки зрения viewer_team
	if hex_owner_team == -1:
		# Нейтральный гекс
		atlas_coords = Vector2i(2, 0)
	elif hex_owner_team == viewer_team:
		# Мой гекс (союзный)
		atlas_coords = Vector2i(0, 0)
	else:
		# Вражеский гекс
		atlas_coords = Vector2i(1, 0)
	
	# Обновляем тайл в OverlayMap
	overlay_map.set_cell(hex_position, 0, atlas_coords, 0)
	overlay_map.notify_runtime_tile_data_update()
	
	var owner_str = ""
	var viewer_str = ""
	match hex_owner_team:
		0: owner_str = "A"
		1: owner_str = "B"
		-1: owner_str = "нейтральный"
		_: owner_str = str(hex_owner_team)
	match viewer_team:
		0: viewer_str = "A"
		1: viewer_str = "B"
		-1: viewer_str = "нейтральный"
		_: viewer_str = str(viewer_team)
	
	Handlers.dprint("🎨 ВИЗУАЛ: Гекс ", hex_position, " владелец=", owner_str, " наблюдатель=", viewer_str, " atlas=", atlas_coords)

func get_hex_at_world_position(world_position: Vector2):
	"""
	Возвращает гекс по мировым координатам
	Конвертирует мировые координаты в координаты тайла
	"""
	if not overlay_map:
		return null
	
	# Конвертируем мировые координаты в локальные координаты OverlayMap
	var local_position = overlay_map.to_local(world_position)
	var hex_coords = overlay_map.local_to_map(local_position)
	
	var hex = get_hex_at_position(hex_coords)
	return hex

### LATE JOINER SYNCHRONIZATION ###

func send_full_map_state_to_new_player(player_id: int):
	"""
	Отправляет новому игроку полное состояние всех захваченных гексов
	И НАЧАЛЬНЫЕ ОЧКИ
	Вызывается только на сервере при подключении нового игрока
	"""
	if not is_multiplayer_authority():
		Handlers.dprint("⚠️ SYNC: send_full_map_state_to_new_player вызвана не на сервере!")
		return
	
	# Проверяем является ли это ботом
	var is_bot = _is_player_bot(player_id)
	Handlers.dprint("🔍 SYNC DEBUG: send_full_map_state для player_id: ", player_id, " is_bot: ", is_bot)
	
	# Отправляем очки и баланс новому игроку (только если не бот)
	if player_points.has(player_id) and not is_bot:
		_send_match_balance_to_player(player_id)
		_sync_points_for_player(player_id, false)
		Handlers.dprint("📡 SYNC: Отправлены очки игроку ", player_id)
	elif is_bot:
		Handlers.dprint("🤖 SYNC: Пропускаем отправку очков боту ", player_id)
	
	# Проверяем что гексы инициализированы
	if hexes_dict.is_empty():
		Handlers.dprint("⚠️ SYNC: Гексы еще не инициализированы, пропускаем синхронизацию")
		return
	
	# Собираем данные о всех захваченных гексах
	var captured_hexes: Array = []
	
	for hex_pos in hexes_dict.keys():
		var hex = hexes_dict[hex_pos]
		if hex.team_owner != -1:  # Только захваченные гексы
			captured_hexes.append({
				"position": hex_pos,
				"team_owner": hex.team_owner,
				"capture_progress": hex.capture_progress,
				"capturing_team": hex.capturing_team,
				"command_units": hex.command_units.map(func(unit): return unit.name if unit else "")
			})
	
	# Отправляем состояние карты (ботам тоже нужно знать состояние карты)
	Handlers.dprint("📡 SYNC: Отправляем ", captured_hexes.size(), " захваченных гексов игроку ", player_id)
	if _is_connected_remote_peer(player_id):
		sync_full_map_state.rpc_id(player_id, captured_hexes)

@rpc("any_peer", "reliable")
func sync_full_map_state(captured_hexes_data: Array):
	"""
	RPC функция для получения полного состояния карты на клиенте
	"""
	if multiplayer.is_server():
		return
	
	Handlers.dprint("📥 SYNC: Получили данные о ", captured_hexes_data.size(), " захваченных гексах")
	
	# Применяем состояние к каждому гексу
	for hex_data in captured_hexes_data:
		var hex_pos = hex_data["position"]
		var hex = get_hex_at_position(hex_pos)
		
		if hex:
			hex.team_owner = hex_data["team_owner"]
			hex.capture_progress = hex_data["capture_progress"]
			hex.capturing_team = hex_data["capturing_team"]
			
			# Очищаем старые ссылки на command_units
			hex.command_units.clear()
			
			# Восстанавливаем ссылки на command_units по именам
			for unit_name in hex_data["command_units"]:
				if unit_name and unit_name != "":
					var unit = get_unit_by_name(unit_name)
					if unit:
						hex.command_units.append(unit)
			
			Handlers.dprint("✅ SYNC: Обновлен гекс ", hex_pos, " team: ", hex.team_owner, " progress: ", hex.capture_progress)
			
			# Обновляем визуал для этого гекса
			# Получаем команду локального игрока для правильного отображения
			var local_player_team = 0  # По умолчанию команда A
			if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
				local_player_team = Handlers.TeamHandler.my_profile.team
			_update_overlay_visual(hex_pos, hex.team_owner, local_player_team)
		else:
			Handlers.dprint("❌ SYNC: Гекс не найден по позиции ", hex_pos)
	
	Handlers.dprint("🎯 SYNC: Синхронизация состояния карты завершена")
	call_deferred("_refresh_client_world_visuals")
