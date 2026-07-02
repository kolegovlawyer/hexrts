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
@onready var timer : Timer = $Timer

func _ready():
	timer.connect("timeout", check_connection_status)
	Handlers.NetworkHandler = self
	
func _exit_tree():
	Handlers.NetworkHandler = null

func start_client(host, port, username):
	global_host = str(host)
	if global_host == "localhost" or global_host == "":
		global_host = "127.0.0.1"
	global_port = int(port)
	nickname = username
	_connect_to_server()

func _connect_to_server() -> void:
	if network.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		network.close()

	var error := network.create_client(global_host, global_port)
	if error != OK:
		push_error("[CLIENT] create_client failed with error %s (host=%s, port=%s)" % [error, global_host, global_port])
		return

	if not _signals_connected:
		multiplayer.server_disconnected.connect(_server_disconnected)
		multiplayer.connection_failed.connect(_on_connection_failed)
		_signals_connected = true

	multiplayer.multiplayer_peer = network
	connected = false
	check_connection = false
	print_rich("[color=green][b][CLIENT] Client started (%s:%s)[/b][/color]" % [global_host, global_port])

func reconnect():
	if network.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		network.close()
	var error := network.create_client(global_host, global_port)
	if error != OK:
		push_error("[CLIENT] reconnect failed with error %s" % error)
		return
	multiplayer.multiplayer_peer = network
	connected = false
	check_connection = false
	print_rich("[color=yellow][b][CLIENT] Client reconnecting[/b][/color]")

func _server_disconnected():
	var was_connected: bool = connected
	connected = false
	if not was_connected:
		return
	print_rich("[color=red][b][CLIENT] Disconnected from server[/b][/color]")
	reconnect()

func _on_connection_failed():
	connected = false
	check_connection = false
	timer.stop()
	push_error("[CLIENT] Connection failed (%s:%s). Check that the server is running and the port is correct." % [global_host, global_port])

@rpc("authority", "reliable")
func set_map(map_name:String):
	Handlers.GameHandler.set_map(map_name)

func check_connection_status():
	if network.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		print_rich("[color=red][b][CLIENT] Cannot connect after timeout[/b][/color]")
	check_connection = false

func _process(_delta):
	if multiplayer.multiplayer_peer == null:
		return

	match network.get_connection_status():
		MultiplayerPeer.CONNECTION_CONNECTED:
			if not connected:
				print_rich("[color=green][b][CLIENT] Client connected to server[/b][/color]")
				connected = true
				check_connection = false
				timer.stop()
				emit_signal("client_connected")
		MultiplayerPeer.CONNECTION_CONNECTING:
			if not check_connection:
				timer.start(timeout)
				check_connection = true
				print_rich("[color=yellow][b][CLIENT] Connecting[/b][/color]")
		MultiplayerPeer.CONNECTION_DISCONNECTED:
			if connected:
				print_rich("[color=red][b][CLIENT] Connection disconnected[/b][/color]")
				connected = false
			
