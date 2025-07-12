class_name GameManager extends Node

var game_type = "UNKNOWN"
var map
@onready var units_dict: Dictionary[String, BaseUnit] = {}

# Called when the node enters the scene tree for the first time.
func _ready():
	set_multiplayer_authority(1)
	Handlers.GameHandler = self

# Delete handler on scene exit
func _exit_tree():
	Handlers.GameHandler = null

func instantiate_network():
	if game_type.to_lower() == "server":
		add_child(load("res://scenes/server/server.tscn").instantiate())
	else:
		add_child(load("res://scenes/client/client.tscn").instantiate())

func set_map(map_name:String):
	map = map_name
	#var map_obj = load("res://scenes/maps/%s.tscn" % map).instantiate()
	var map_obj = load("res://scenes/maps/test_world_1.tscn").instantiate()
	for map_node in get_node("Map").get_children():
		map_node.queue_free()
	get_node("Map").add_child(map_obj)
	#$MultiplayerSpawner.spawn_path = map_obj

func create_camera(game_type):
	if game_type == 'Client':
		var camera = load("res://scenes/client/camera_2d.tscn").instantiate()
		add_child(camera)
		Handlers.UIHandler.camera = camera
	elif game_type == 'Server':
		var camera = load("res://scenes/client/camera_2d.tscn").instantiate()
		add_child(camera)

func create_ui():
	var ui = load("res://scenes/client/base_ui.tscn").instantiate()
	$"%UICanvasLayer".add_child(ui)

func set_type_server(port:int):
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
