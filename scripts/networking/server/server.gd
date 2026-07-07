extends Node

var network = ENetMultiplayerPeer.new()
var http_request := HTTPRequest.new()
var global_port : int
# Интерфейс, на котором слушает сервер. Принимается ТОЛЬКО IP-литерал (IPv4/IPv6),
# имя хоста (напр. WIN-J79V8KOQ600) здесь не резолвится.
# "::1"       - IPv6-loopback (эксперимент: VPN на WireGuard/AmneziaWG + KillSwitch
#               часто фильтруют только IPv4, поэтому IPv6-петля может остаться рабочей).
# "127.0.0.1" - IPv4-loopback (только эта машина).
# "0.0.0.0"   - все IPv4-интерфейсы (loopback + LAN) для реальной игры по сети.
# "*"         - все интерфейсы (IPv4 + IPv6).
var bind_ip : String = "0.0.0.0"
#var bind_ip : String = "127.0.0.1"
const TRACE_PATH := "user://network_trace.log"
@onready var spawner : MultiplayerSpawner

# Called when the node enters the scene tree for the first time.

func _ready():
	add_child(http_request)
	Handlers.NetworkHandler = self
	spawner = Handlers.GameHandler.get_node("./MultiplayerSpawner")
	_trace("READY bind_ip=%s" % bind_ip)

func _exit_tree():
	_trace("EXIT_TREE: closing server network")
	# Явно закрываем сокет, чтобы порт освобождался сразу и не оставались
	# "зависшие" сокеты (иначе иногда помогает только перезагрузка ПК).
	if network:
		network.close()
	if multiplayer.multiplayer_peer == network:
		multiplayer.multiplayer_peer = null
	Handlers.NetworkHandler = null

@rpc("authority", "reliable")
func set_map(map_name:String): # TODO неиспользуемая функция
	pass

func _peer_connected(player_id):
	_trace("SIGNAL peer_connected player_id=%s" % str(player_id))
	print_rich("[color=green][b][SERVER] Player %s connected[/b][/color]" % player_id)
	rpc_id(player_id, "set_map", Handlers.GameHandler.map)
	
	# Отправляем новому игроку актуальное состояние всех захваченных гексов
	# Небольшая задержка чтобы убедиться что клиент инициализировался
	await get_tree().create_timer(0.5).timeout
	if Handlers.GameHandler:
		Handlers.GameHandler.send_full_map_state_to_new_player(player_id)

func _peer_disconnected(player_id):
	_trace("SIGNAL peer_disconnected player_id=%s" % str(player_id))
	Handlers.TeamHandler.rpc("remove_from_team", player_id)
	print_rich("[color=red][b][SERVER] Player %s disconnected[/b][/color]" % player_id)

func start_server(port):
	_trace("START_SERVER called port=%s bind_ip=%s" % [str(port), bind_ip])
	# Привязываемся к конкретному интерфейсу ДО create_server.
	network.set_bind_ip(bind_ip)
	var error := network.create_server(int(port))
	_trace("CREATE_SERVER result=%s port=%s bind_ip=%s" % [str(error), str(port), bind_ip])
	if error != OK:
		push_error("[SERVER] create_server failed with error %s (port=%s, bind_ip=%s)" % [error, port, bind_ip])
		_trace("CREATE_SERVER failed")
		return
	multiplayer.multiplayer_peer = network
	
	# TODO: START DB COONECTION
	
	network.connect("peer_connected", _peer_connected)
	network.connect("peer_disconnected", _peer_disconnected)
	
	global_port = port
	print_rich("[color=green][b][SERVER] Server started (bind %s:%s)[/b][/color]" % [bind_ip, port])
	_trace("SERVER_STARTED bind=%s port=%s unique_id=%s" % [bind_ip, str(port), str(multiplayer.get_unique_id())])


func _on_update_info_timer_timeout() -> void:
	var body = JSON.new().stringify({ "map": Handlers.GameHandler.map, "port":global_port, "secret":"SIMBALOX"})
	http_request.cancel_request()
	var error = http_request.request("http://127.0.0.1:3000/api/servers/submit", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if error != OK:
		push_error("An error occurred in the HTTP request.")
		_trace("HTTP submit failed error=%s" % str(error))

func _trace(message: String) -> void:
	var line := "[%s][SERVER] %s" % [Time.get_datetime_string_from_system(), message]
	print(line)
	printerr(line)
	var file := FileAccess.open(TRACE_PATH, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_line(line)
		file.close()
