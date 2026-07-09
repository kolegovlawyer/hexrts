class_name ServerUI extends Control

## Серверный UI: добавление ботов, квоты, лог решений ИИ.

@onready var add_bot_button: Button = get_node("%AddBotButton")
@onready var team_option: OptionButton = get_node("%TeamOption")
@onready var bots_list: VBoxContainer = get_node("%BotsList")
@onready var quota_label: RichTextLabel = get_node("%QuotaLabel")
@onready var debug_log: RichTextLabel = get_node("%DebugLog")

var bot_counter: int = 1
var _bot_log_connections: Dictionary = {}


func _ready() -> void:
	if not is_multiplayer_authority():
		hide()
		return
	call_deferred("_attach_to_ui_layer")
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(_refresh_debug_panel)
	timer.autostart = true
	add_child(timer)
	_refresh_debug_panel()
	print("SERVER UI: панель ботов готова")


func _attach_to_ui_layer() -> void:
	if Handlers.GameHandler == null:
		return
	var canvas: CanvasLayer = Handlers.GameHandler.get_node_or_null("%UICanvasLayer") as CanvasLayer
	if canvas == null:
		return
	reparent(canvas)
	canvas.layer = maxi(canvas.layer, 10)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Panel.mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100


func _on_add_bot_button_pressed() -> void:
	if not is_multiplayer_authority():
		return
	var selected_team: int = team_option.get_selected_id()
	var bot_name := "Bot_%d" % bot_counter
	bot_counter += 1
	_create_server_bot(bot_name, GameTypes.Teams.values()[selected_team])


func _create_server_bot(bot_name: String, team: GameTypes.Teams) -> void:
	var bot_id := -(bot_counter + 1000)
	var bot_ai: Bot = preload("res://scripts/bot.gd").new()
	bot_ai.name = "ServerBot_%s" % bot_name
	if Handlers.GameHandler == null:
		return
	Handlers.GameHandler.add_child(bot_ai)
	bot_ai.initialize_bot(bot_id, team, bot_name)
	Handlers.GameHandler.register_bot(bot_ai)
	if Handlers.TeamHandler:
		Handlers.TeamHandler.add_bot_to_team(bot_id, team)
	_assign_fob_to_bot(bot_ai, team)
	call_deferred("_force_bot_activation", bot_ai)
	_connect_bot_debug(bot_ai)
	print("SERVER UI: бот %s создан (id=%d)" % [bot_name, bot_id])


func _connect_bot_debug(bot: Bot) -> void:
	if bot in _bot_log_connections:
		return
	var callable := _on_bot_debug_updated.bind(bot)
	if not bot.debug_updated.is_connected(callable):
		bot.debug_updated.connect(callable)
	_bot_log_connections[bot] = callable
	bot._log_debug("бот зарегистрирован в UI")


func _on_bot_debug_updated(_snapshot: Dictionary, bot: Bot) -> void:
	if not is_instance_valid(bot):
		return
	_refresh_debug_panel()


func _force_bot_activation(bot: Bot) -> void:
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(bot):
		bot._make_strategic_decisions()
		bot._check_spawn_opportunity()


func _assign_fob_to_bot(bot: Bot, team: GameTypes.Teams) -> void:
	var team_fob_group := "team_%d_fobs" % int(team)
	var team_fobs := get_tree().get_nodes_in_group(team_fob_group)
	for fob in team_fobs:
		if fob.owner_id == 0 or fob.owner_id == 2 or fob.owner_id == 3:
			fob.owner_id = bot.bot_id
			call_deferred("_force_bot_spawn", bot, fob)
			return
	if team_fobs.size() > 0:
		team_fobs[0].owner_id = bot.bot_id
		call_deferred("_force_bot_spawn", bot, team_fobs[0])


func _force_bot_spawn(bot: Bot, fob: Node) -> void:
	if Handlers.GameHandler == null or not Handlers.GameHandler.player_points.has(bot.bot_id):
		return
	var bot_points: float = Handlers.GameHandler.player_points[bot.bot_id]["recruitment_points"]
	if bot_points < 20:
		return
	if fob.has_method("add_spawn_order"):
		var cmd_preset := UnitPreset.create_command_default()
		fob.add_spawn_order(
			"command_unit",
			cmd_preset.get_cost(),
			bot.bot_id,
			cmd_preset.get_spawn_time(),
			cmd_preset.to_spawn_snapshot()
		)


func _update_bots_list() -> void:
	if Handlers.GameHandler == null:
		return
	for child in bots_list.get_children():
		child.queue_free()
	for bot in Handlers.GameHandler.active_bots:
		if not is_instance_valid(bot):
			continue
		_connect_bot_debug(bot)
		var team_name := "A" if bot.bot_team == GameTypes.Teams.TEAM_A else "B"
		var snap: Dictionary = bot.get_debug_snapshot()
		var bot_info := Label.new()
		bot_info.text = (
			"%s (T%s) | КШМ %d | боец %d/%d | арт %d/%d | %.0f очков"
			% [
				bot.bot_name,
				team_name,
				snap.get("command_total", 0),
				snap.get("fighters", 0),
				snap.get("fighters_needed", 0),
				snap.get("artillery", 0),
				snap.get("artillery_needed", 0),
				snap.get("points", 0.0),
			]
		)
		var row := HBoxContainer.new()
		row.add_child(bot_info)
		var remove_button := Button.new()
		remove_button.text = "X"
		remove_button.custom_minimum_size = Vector2(28, 20)
		remove_button.pressed.connect(_remove_bot.bind(bot))
		row.add_child(remove_button)
		bots_list.add_child(row)


func _refresh_debug_panel() -> void:
	_update_bots_list()
	if Handlers.GameHandler == null:
		return
	var quota_lines: PackedStringArray = []
	var log_lines: PackedStringArray = []
	for bot in Handlers.GameHandler.active_bots:
		if not is_instance_valid(bot):
			continue
		var snap: Dictionary = bot.get_debug_snapshot()
		quota_lines.append(
			"[b]%s[/b]  очки: [color=#7fd7ff]%.0f[/color]  |  "
			% [snap.get("bot_name", "?"), snap.get("points", 0.0)]
		)
		quota_lines.append(
			"  КШМ: %d+%d → нужно для арт: ≥2 всего  |  "
			% [snap.get("command_units", 0), snap.get("command_pending", 0)]
		)
		quota_lines.append(
			"бойцы: %d+%d / %d  |  "
			% [snap.get("fighters", 0), snap.get("fighters_pending", 0), snap.get("fighters_needed", 0)]
		)
		quota_lines.append(
			"арт: [color=#ffd47f]%d+%d / %d[/color] (стоим. %d)  |  "
			% [
				snap.get("artillery", 0),
				snap.get("artillery_pending", 0),
				snap.get("artillery_needed", 0),
				snap.get("artillery_cost", 40),
			]
		)
		quota_lines.append(
			"посл. спавн: [i]%s[/i]  тревоги: %d"
			% [snap.get("last_spawn", ""), snap.get("active_alarms", 0)]
		)
		if str(snap.get("last_block", "")) != "":
			quota_lines.append("  [color=#ff8888]блок: %s[/color]" % snap.get("last_block", ""))
		var bot_log: Array = snap.get("log", [])
		for i in range(maxi(0, bot_log.size() - 8), bot_log.size()):
			log_lines.append("[color=#aaaaaa]%s:[/color] %s" % [snap.get("bot_name", "?"), bot_log[i]])
	if quota_lines.is_empty():
		quota_label.text = "[i]Нет активных ботов[/i]"
	else:
		quota_label.text = "\n".join(quota_lines)
	if log_lines.is_empty():
		debug_log.text = "[i]Лог решений пуст[/i]"
	else:
		debug_log.text = "\n".join(log_lines)


func _remove_bot(bot: Bot) -> void:
	if not is_multiplayer_authority():
		return
	if _bot_log_connections.has(bot):
		var callable: Callable = _bot_log_connections[bot]
		if bot.debug_updated.is_connected(callable):
			bot.debug_updated.disconnect(callable)
		_bot_log_connections.erase(bot)
	for fob in get_tree().get_nodes_in_group("fobs"):
		if fob.owner_id == bot.bot_id:
			fob.owner_id = 0
	for unit in bot.bot_units:
		if is_instance_valid(unit):
			unit.queue_free()
	if Handlers.GameHandler:
		Handlers.GameHandler.unregister_bot(bot)
	bot.queue_free()
	_refresh_debug_panel()
