extends Node

signal client_connected

var network = ENetMultiplayerPeer.new()
var nickname : String = "Player"
var check_connection : bool = false
var global_host
var global_port
var timeout = 5
var disconnect_reason = "Timed out"
var connected = false
var _signals_connected := false
var _last_connection_status: int = -1
@onready var timer : Timer = $Timer
const TRACE_PATH := "user://network_trace.log"

func _ready():
	timer.connect("timeout", check_connection_status)
	Handlers.NetworkHandler = self
	_trace("READY")
	
func _exit_tree():
	_trace("EXIT_TREE: closing client network")
	# Явно закрываем сокет клиента при выходе, чтобы не оставались зависшие
	# соединения/сокеты (частая причина того, что помогает только перезагрузка).
	if network:
		network.close()
	if multiplayer.multiplayer_peer == network:
		multiplayer.multiplayer_peer = null
	Handlers.NetworkHandler = null

func start_client(host, port, username):
	_trace("START_CLIENT called host=%s port=%s nickname=%s" % [str(host), str(port), str(username)])
	global_host = str(host)
	# ЭКСПЕРИМЕНТ: используем IPv6-loopback (::1) вместо IPv4 (127.0.0.1).
	# Многие VPN (WireGuard/AmneziaWG + KillSwitch) фильтруют только IPv4,
	# поэтому IPv6-петля может остаться незаблокированной.
	if global_host == "localhost" or global_host == "" or global_host == "127.0.0.1":
		#global_host = "185.185.70.201"
		#global_host = "10.8.0.2"
		global_host == "127.0.0.1"
	global_port = int(port)
	nickname = username
	_trace("START_CLIENT normalized host=%s port=%s" % [global_host, global_port])
	_connect_to_server()

func _connect_to_server() -> void:
	_trace("CONNECT_BEGIN status=%s peer_is_null=%s" % [_status_to_text(network.get_connection_status()), str(multiplayer.multiplayer_peer == null)])
	if network.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		_trace("CONNECT_BEGIN: force close old ENet peer")
		network.close()

	# Для loopback жёстко привязываем исходящий сокет к той же петле (IPv4/IPv6),
	# чтобы ОС не выбрала VPN-адаптер источником.
	if _is_loopback_host(global_host):
		network.set_bind_ip(global_host)
		_trace("BIND_IP set to loopback %s" % global_host)
	else:
		network.set_bind_ip("*")
		_trace("BIND_IP set to *")

	var error := network.create_client(global_host, global_port)
	_trace("CREATE_CLIENT result=%s(%s) host=%s port=%s" % [str(error), _error_to_text(error), global_host, str(global_port)])
	if error != OK:
		push_error("[CLIENT] create_client failed with error %s (host=%s, port=%s)" % [error, global_host, global_port])
		_trace("CREATE_CLIENT failed")
		return

	if not _signals_connected:
		multiplayer.server_disconnected.connect(_server_disconnected)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_signals_connected = true
		_trace("MULTIPLAYER signals connected")

	multiplayer.multiplayer_peer = network
	connected = false
	check_connection = false
	print_rich("[color=green][b][CLIENT] Client started (%s:%s)[/b][/color]" % [global_host, global_port])
	_trace("CLIENT_STARTED host=%s port=%s" % [global_host, str(global_port)])

func reconnect():
	print_rich("[color=yellow][b][CLIENT] Client reconnecting[/b][/color]")
	_trace("RECONNECT called")
	_connect_to_server()

func _server_disconnected():
	var was_connected: bool = connected
	connected = false
	_trace("SIGNAL server_disconnected was_connected=%s" % str(was_connected))
	if not was_connected:
		return
	print_rich("[color=red][b][CLIENT] Disconnected from server[/b][/color]")
	reconnect()

func _on_connection_failed():
	connected = false
	check_connection = false
	timer.stop()
	push_error("[CLIENT] Connection failed (%s:%s). Check that the server is running and the port is correct." % [global_host, global_port])
	_trace("SIGNAL connection_failed host=%s port=%s status=%s" % [global_host, str(global_port), _status_to_text(network.get_connection_status())])
	_trace("TRACE_FILE location: %s" % ProjectSettings.globalize_path(TRACE_PATH))

func _on_connected_to_server() -> void:
	_trace("SIGNAL connected_to_server id=%s status=%s" % [str(multiplayer.get_unique_id()), _status_to_text(network.get_connection_status())])

func _on_peer_connected(peer_id: int) -> void:
	_trace("SIGNAL peer_connected peer_id=%s" % str(peer_id))

func _on_peer_disconnected(peer_id: int) -> void:
	_trace("SIGNAL peer_disconnected peer_id=%s" % str(peer_id))

func _is_loopback_host(host: String) -> bool:
	return host in ["127.0.0.1", "localhost", "::1"]

@rpc("authority", "reliable")
func set_map(map_name:String):
	Handlers.GameHandler.set_map(map_name)

func check_connection_status():
	if network.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		print_rich("[color=red][b][CLIENT] Cannot connect after timeout[/b][/color]")
		_trace("TIMEOUT reached status=%s" % _status_to_text(network.get_connection_status()))
	check_connection = false

func _process(_delta):
	if multiplayer.multiplayer_peer == null:
		return
	
	var status := network.get_connection_status()
	if status != _last_connection_status:
		_last_connection_status = status
		_trace("STATUS_CHANGED -> %s" % _status_to_text(status))

	match status:
		MultiplayerPeer.CONNECTION_CONNECTED:
			if not connected:
				print_rich("[color=green][b][CLIENT] Client connected to server[/b][/color]")
				connected = true
				check_connection = false
				timer.stop()
				emit_signal("client_connected")
				_trace("EMIT client_connected id=%s" % str(multiplayer.get_unique_id()))
		MultiplayerPeer.CONNECTION_CONNECTING:
			if not check_connection:
				timer.start(timeout)
				check_connection = true
				print_rich("[color=yellow][b][CLIENT] Connecting[/b][/color]")
				_trace("CONNECTING timer_started timeout=%s" % str(timeout))
		MultiplayerPeer.CONNECTION_DISCONNECTED:
			if connected:
				print_rich("[color=red][b][CLIENT] Connection disconnected[/b][/color]")
				connected = false
				_trace("DISCONNECTED after previously connected")

func _trace(message: String) -> void:
	var line := "[%s][CLIENT] %s" % [Time.get_datetime_string_from_system(), message]
	print(line)
	printerr(line)
	var file := FileAccess.open(TRACE_PATH, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_line(line)
		file.close()

func _status_to_text(status: int) -> String:
	match status:
		MultiplayerPeer.CONNECTION_DISCONNECTED:
			return "DISCONNECTED"
		MultiplayerPeer.CONNECTION_CONNECTING:
			return "CONNECTING"
		MultiplayerPeer.CONNECTION_CONNECTED:
			return "CONNECTED"
		_:
			return "UNKNOWN(%s)" % str(status)

func _error_to_text(error_code: int) -> String:
	match error_code:
		OK:
			return "OK"
		ERR_UNAVAILABLE:
			return "ERR_UNAVAILABLE"
		ERR_ALREADY_IN_USE:
			return "ERR_ALREADY_IN_USE"
		ERR_CANT_CREATE:
			return "ERR_CANT_CREATE"
		ERR_INVALID_PARAMETER:
			return "ERR_INVALID_PARAMETER"
		ERR_CANT_RESOLVE:
			return "ERR_CANT_RESOLVE"
		ERR_CONNECTION_ERROR:
			return "ERR_CONNECTION_ERROR"
		_:
			return "ERR_%s" % str(error_code)
			
