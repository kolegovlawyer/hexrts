extends Node

var network = ENetMultiplayerPeer.new()
var http_request := HTTPRequest.new()
var global_port : int
# Интерфейс, на котором слушает сервер.
# "127.0.0.1" - только эта машина (надёжно для локального теста, не зависит от VPN/адаптеров).
# "0.0.0.0"   - все IPv4-интерфейсы (loopback + LAN) для реальной игры по сети.
# ВНИМАНИЕ: при активном VPN/виртуальном адаптере "*" и "0.0.0.0" иногда садятся на
# чужой адаптер (напр. 10.x.x.x) без loopback, из-за чего клиент на 127.0.0.1 не подключается.
var bind_ip : String = "127.0.0.1"
@onready var spawner : MultiplayerSpawner

# Called when the node enters the scene tree for the first time.

func _ready():
	add_child(http_request)
	Handlers.NetworkHandler = self
	spawner = Handlers.GameHandler.get_node("./MultiplayerSpawner")

func _exit_tree():
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
	print_rich("[color=green][b][SERVER] Player %s connected[/b][/color]" % player_id)
	rpc_id(player_id, "set_map", Handlers.GameHandler.map)
	
	# Отправляем новому игроку актуальное состояние всех захваченных гексов
	# Небольшая задержка чтобы убедиться что клиент инициализировался
	await get_tree().create_timer(0.5).timeout
	if Handlers.GameHandler:
		Handlers.GameHandler.send_full_map_state_to_new_player(player_id)

func _peer_disconnected(player_id):
	Handlers.TeamHandler.rpc("remove_from_team", player_id)
	print_rich("[color=red][b][SERVER] Player %s disconnected[/b][/color]" % player_id)

func start_server(port):
	# Привязываемся к конкретному интерфейсу ДО create_server.
	network.set_bind_ip(bind_ip)
	var error := network.create_server(int(port))
	if error != OK:
		push_error("[SERVER] create_server failed with error %s (port=%s, bind_ip=%s)" % [error, port, bind_ip])
		return
	multiplayer.multiplayer_peer = network
	
	# TODO: START DB COONECTION
	
	network.connect("peer_connected", _peer_connected)
	network.connect("peer_disconnected", _peer_disconnected)
	
	global_port = port
	print_rich("[color=green][b][SERVER] Server started (bind %s:%s)[/b][/color]" % [bind_ip, port])


func _on_update_info_timer_timeout() -> void:
	var body = JSON.new().stringify({ "map": Handlers.GameHandler.map, "port":global_port, "secret":"SIMBALOX"})
	http_request.cancel_request()
	var error = http_request.request("http://127.0.0.1:3000/api/servers/submit", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if error != OK:
		push_error("An error occurred in the HTTP request.")
