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
@onready var timer : Timer = $Timer

func _ready():
	timer.connect("timeout", check_connection_status)
	Handlers.NetworkHandler = self
	
func _exit_tree():
	Handlers.NetworkHandler = null

func start_client(host, port, username):
	var error = network.create_client(host, port) # MAKE CHECK FOR CONNECTION ERROR
	multiplayer.connect("server_disconnected", _server_disconnected)
	global_host = host
	global_port = port
	nickname = username
	multiplayer.multiplayer_peer = network
	print_rich("[color=green][b][CLIENT] Client started[/b][/color]")

func reconnect():
	network.close()
	var error = network.create_client(global_host, global_port)
	multiplayer.multiplayer_peer = network
	print_rich("[color=yellow][b][CLIENT] Client reconnecting[/b][/color]")

func _server_disconnected():
	print_rich("[color=red][b][CLIENT] Disconnected from server[/b][/color]")
	connected = false
	reconnect()

@rpc("authority", "reliable")
func set_map(map_name:String):
	Handlers.GameHandler.set_map(map_name)

func check_connection_status():
	if network.get_connection_status() != network.CONNECTION_CONNECTED:
		print_rich("[color=red][b][CLIENT] Cannot connect afrter timeout[/b][/color]") # Disconned + return to lobby
	check_connection = false

func _process(delta):
	if multiplayer.get_unique_id():
		if network.get_connection_status() == network.CONNECTION_DISCONNECTED:
			print_rich("[color=red][b][CLIENT] Connection disconnected[/b][/color]")
			print("")
		elif network.get_connection_status() == network.CONNECTION_CONNECTED and not connected:
			print_rich("[color=green][b][CLIENT] Client connected to server[/b][/color]")
			connected = true
			emit_signal("client_connected")
		elif network.get_connection_status() == network.CONNECTION_CONNECTING:
			if not check_connection:
				timer.start(timeout)
				check_connection = true
				print_rich("[color=yellow][b][CLIENT] Connecting[/b][/color]")
			
