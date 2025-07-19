extends Control

# It will be great to have SceneManager
# :) 
var http_request := HTTPRequest.new()


# Called when the node enters the scene tree for the first time.
func _ready():
	add_child(http_request)
	http_request.request_completed.connect(self._refresh_request_completed)

func _refresh_request_completed(result, response_code, headers, body):
	if response_code == 200:
		var json = JSON.new()
		json.parse(body.get_string_from_utf8())
		var response = json.get_data()
		print(response)
		for server in response.get("servers"):
			var server_node : Control = load("res://scenes/server_element.tscn").instantiate()
			%ServerListBox.add_child(server_node)
			server_node.get_node("Map").text = server.get("map")
			var server_button = server_node.get_node("Button")
			server_button.connect("pressed", _on_serverlist_join_button_pressed.bind(server_button, server.get("ip"), server.get("port")))

func _on_join_button_pressed(host=null, port=null, team=null):
	#if authorization() == true:
	get_tree().get_root().add_child(load("res://scenes/game.tscn").instantiate())
	
	if not host:
		host = $"Join-Tab/HostEdit".text
	if not port:
		port = int($"Join-Tab/PortEdit".text)
	if not team:
		team = $"Join-Tab/TeamButton".get_selected_id()
	
	var nickname = $"Join-Tab/NickEdit".text
	
	# Обычный клиент (убираем поддержку ботов через клиент)
	Handlers.GameHandler.set_type_client(host, port, nickname)
	Handlers.NetworkHandler.connect("client_connected", Handlers.TeamHandler.on_connect.bind(team))
	
	get_tree().get_root().get_node("./Lobby").queue_free()
	

func _on_host_button_pressed():
	var port = int($"Host-Tab/PortEdit".text)
	var map = $"Host-Tab/OptionButton".get_item_text($"Host-Tab/OptionButton".get_selected_id())
	
	get_tree().get_root().add_child(load("res://scenes/game.tscn").instantiate()) 
	
	Handlers.GameHandler.set_type_server(port)
	Handlers.GameHandler.set_map(map)
	Handlers.TeamHandler.on_connect()
	
	get_tree().get_root().get_node("./Lobby").queue_free()
	

func _on_refresh_button_pressed() -> void:
	for child in %ServerListBox.get_children():
		child.queue_free()
	var error = http_request.request("http://127.0.0.1:3000/api/servers") # change to dev.digitalpunks.ru
	if error != OK:
		push_error("An error occurred in the HTTP request.")

func _on_serverlist_join_button_pressed(call_node=null,host=null, port=null):
	_on_join_button_pressed(host, port, call_node.get_node("../TeamButton").get_selected_id())
