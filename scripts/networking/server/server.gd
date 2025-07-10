extends Node

var network = ENetMultiplayerPeer.new()
var http_request := HTTPRequest.new()
var global_port : int
@onready var spawner : MultiplayerSpawner

# Called when the node enters the scene tree for the first time.

func _ready():
	add_child(http_request)
	Handlers.NetworkHandler = self
	spawner = Handlers.GameHandler.get_node("./MultiplayerSpawner")

func _exit_tree():
	Handlers.NetworkHandler = null

@rpc("authority", "reliable")
func set_map(map_name:String): # TODO неиспользуемая функция
	pass

func _peer_connected(player_id):
	print_rich("[color=green][b][SERVER] Player %s connected[/b][/color]" % player_id)
	rpc_id(player_id, "set_map", Handlers.GameHandler.map)

func _peer_disconnected(player_id):
	Handlers.TeamHandler.rpc("remove_from_team", player_id)
	print_rich("[color=red][b][SERVER] Player %s disconnected[/b][/color]" % player_id)

func start_server(port):
	network.create_server(port)
	multiplayer.multiplayer_peer = network
	
	# TODO: START DB COONECTION
	
	network.connect("peer_connected", _peer_connected)
	network.connect("peer_disconnected", _peer_disconnected)
	
	global_port = port
	print_rich("[color=green][b][SERVER] Server started[/b][/color]")


func _on_update_info_timer_timeout() -> void:
	var body = JSON.new().stringify({ "map": Handlers.GameHandler.map, "port":global_port, "secret":"SIMBALOX"})
	http_request.cancel_request()
	var error = http_request.request("http://127.0.0.1:3000/api/servers/submit", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if error != OK:
		push_error("An error occurred in the HTTP request.")
