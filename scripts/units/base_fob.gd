class_name fob extends StaticBody2D

signal fob_destroyed(destroyed_fob: fob, owner_player_id: int)

const FOG_VISION_RADIUS := 250.0
const DEFAULT_MAX_HEALTH := 500
const DEFAULT_MAX_SHIELD := 150
const SHIELD_REGEN_RATE := 2.0
const SHIELD_REGEN_DELAY := 5.0
# Слой 10 — только клик мышью; mask=0 → нет физики с юнитами/картой.
const PICK_COLLISION_LAYER := 512

@onready var sprite = get_node("%Sprite")
@onready var spawn_bar = get_node("%SpawnProgress")
@onready var spawn_queue_label = get_node("%SpawnQueueLabel")
@onready var health_bar = get_node("%HealthBar")
@onready var shield_bar = get_node("%ShieldBar")
@onready var visibility_area: Area2D = get_node("%VisibilityArea")

var vision_radius: float = FOG_VISION_RADIUS

var UID: String = ""
var owner_team = null
var is_destroyed: bool = false

@export var max_health: int = DEFAULT_MAX_HEALTH
@export var max_shield: int = DEFAULT_MAX_SHIELD
var health: int = DEFAULT_MAX_HEALTH
var shield: int = DEFAULT_MAX_SHIELD

var _health: int = DEFAULT_MAX_HEALTH
var _shield: int = DEFAULT_MAX_SHIELD

var has_vision_on: Array[BaseUnitServer] = []
var _enemies_in_vision: Array[BaseUnitServer] = []

var shield_regeneration_timer: Timer

# Система отложенного спавна
const UNIT_SPAWN_DELAY: float = 3.0
const COMMAND_UNIT_SPAWN_DELAY: float = 6.0

var spawn_queue: Array = []
var spawn_timer: Timer
var ui_update_timer: Timer

@export var team: int
var owner_id = 0:
	set(value):
		var resolved_id := _resolve_owner_id(value)
		if owner_id == resolved_id:
			return
		owner_id = resolved_id
		_resolve_owner_team()
		update_visual()
		if is_multiplayer_authority():
			call_deferred("_refresh_existing_vision")

var selected: bool = false:
	set(value):
		selected = value
		if value == true:
			show_fob_panel()
			Handlers.UnitSelectionHandler.selected_fob = self
		else:
			Handlers.UIHandler.delete_fob_panel()
			Handlers.UnitSelectionHandler.selected_fob = null

func _ready() -> void:
	add_to_group("fobs")
	_init_vitals_ui()
	_setup_pick_only_collision()

	if is_multiplayer_authority():
		_health = max_health
		_shield = max_shield
		UID = "fob_%d" % get_instance_id()
		_setup_vision_area()
		_setup_spawn_timer()
		_setup_ui_update_timer()
		_setup_shield_regeneration_timer()
		_resolve_owner_team()
		if Handlers.GameHandler and Handlers.GameHandler.has_method("register_fob"):
			Handlers.GameHandler.register_fob(self)
	else:
		update_visual()
		_initialize_spawn_ui()


func _setup_pick_only_collision() -> void:
	collision_layer = PICK_COLLISION_LAYER
	collision_mask = 0
	input_pickable = true
	var body_shape: CollisionShape2D = get_node_or_null("CollisionShape") as CollisionShape2D
	if body_shape:
		body_shape.disabled = false
	if not input_event.is_connected(handle_input):
		input_event.connect(handle_input)

func _exit_tree() -> void:
	if is_multiplayer_authority() and Handlers.GameHandler and Handlers.GameHandler.has_method("unregister_fob"):
		Handlers.GameHandler.unregister_fob(self)
	_clear_vision_links()

func _resolve_owner_id(value) -> int:
	if value is int:
		return value
	if value is PlayerProfile:
		return value.PlayerId
	return int(value) if str(value).is_valid_int() else 0

func _resolve_owner_team() -> void:
	owner_team = null
	if owner_id == 0:
		owner_team = team
		return
	if Handlers.GameHandler:
		var bot_team = Handlers.GameHandler.get_bot_team_by_id(owner_id)
		if bot_team != -1:
			owner_team = bot_team
			return
	if Handlers.TeamHandler:
		var player = Handlers.TeamHandler.find_player_by_id(owner_id)
		if player:
			owner_team = player.team

func get_owner_team():
	return owner_team

func is_alive() -> bool:
	return not is_destroyed and _health > 0

func handle_input(_viewport, event, _shape_idx):
	if Handlers.TeamHandler == null or Handlers.TeamHandler.my_profile == null:
		return
	if owner_id == Handlers.TeamHandler.my_profile.PlayerId:
		if event is InputEventMouseButton and event.button_index == 1:
			if event.pressed == true:
				selected = true
				Handlers.UIHandler.input_state = 2
				Handlers.UIHandler.get_viewport().set_input_as_handled()

func show_fob_panel():
	Handlers.UIHandler.create_fob_panel(self)

func update_visual():
	if owner_id == 0:
		sprite.modulate = GameTypes.enemy_color
		sprite.visibility_layer = 2
		_update_spawn_ui_visibility()
		return
	if Handlers.TeamHandler.my_profile:
		if owner_id == Handlers.TeamHandler.my_profile.PlayerId:
			sprite.modulate = GameTypes.own_color
			sprite.visibility_layer = 1
		elif owner_id in Handlers.TeamHandler.get_team_players(Handlers.TeamHandler.my_profile.PlayerId):
			pass
		else:
			sprite.modulate = GameTypes.enemy_color
			sprite.visibility_layer = 2
	_update_spawn_ui_visibility()
	_update_vitals_bars()

### VITALS ###

func _init_vitals_ui() -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = health
	if shield_bar:
		shield_bar.max_value = max_shield
		shield_bar.value = shield

func _update_vitals_bars() -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = health
		var health_percent := float(health) / float(max_health) if max_health > 0 else 0.0
		if health_percent > 0.7:
			health_bar.modulate = Color.GREEN
		elif health_percent > 0.3:
			health_bar.modulate = Color.YELLOW
		else:
			health_bar.modulate = Color.RED
	if shield_bar:
		shield_bar.max_value = max_shield
		shield_bar.value = shield
		shield_bar.visible = shield > 0

func apply_damage(amount: int, from: BaseUnitServer = null) -> void:
	if not is_multiplayer_authority() or is_destroyed:
		return

	if from and is_instance_valid(from) and Handlers.GameHandler and Handlers.GameHandler.battle_log:
		Handlers.GameHandler.battle_log.on_fob_damaged(self, from)

	var remaining_damage := amount
	if _shield > 0:
		var shield_damage: int = min(_shield, remaining_damage)
		_shield = max(_shield - shield_damage, 0)
		remaining_damage -= shield_damage
		if shield_regeneration_timer:
			shield_regeneration_timer.stop()
			shield_regeneration_timer.wait_time = SHIELD_REGEN_DELAY
			shield_regeneration_timer.start()

	if remaining_damage > 0:
		_health = max(_health - remaining_damage, 0)

	health = _health
	shield = _shield
	_update_vitals_bars()

	rpc("sync_vitals", _health, _shield)

	if _health <= 0:
		_destroy_fob(from)

@rpc("authority", "call_remote", "reliable")
func sync_vitals(new_health_value: int, new_shield_value: int) -> void:
	health = clampi(new_health_value, 0, max_health)
	shield = clampi(new_shield_value, 0, max_shield)
	_health = health
	_shield = shield
	_update_vitals_bars()

@rpc("authority", "call_remote", "reliable")
func sync_health(new_health_value: int) -> void:
	sync_vitals(new_health_value, shield)

@rpc("authority", "call_remote", "reliable")
func sync_shield(new_shield_value: int) -> void:
	sync_vitals(health, new_shield_value)

func _setup_shield_regeneration_timer() -> void:
	shield_regeneration_timer = Timer.new()
	shield_regeneration_timer.one_shot = true
	shield_regeneration_timer.timeout.connect(_on_shield_regen_timeout)
	add_child(shield_regeneration_timer)

func _on_shield_regen_timeout() -> void:
	if not is_multiplayer_authority() or is_destroyed or _shield >= max_shield:
		return
	_shield = min(_shield + int(SHIELD_REGEN_RATE * SHIELD_REGEN_DELAY), max_shield)
	shield = _shield
	rpc("sync_vitals", _health, _shield)
	if _shield < max_shield:
		shield_regeneration_timer.start()

func _destroy_fob(_from: BaseUnitServer = null) -> void:
	if is_destroyed:
		return
	is_destroyed = true
	_clear_vision_links()
	if Handlers.GameHandler and Handlers.GameHandler.battle_log:
		Handlers.GameHandler.battle_log.on_fob_destroyed(self)
	fob_destroyed.emit(self, owner_id)
	if Handlers.GameHandler and Handlers.GameHandler.has_method("handle_fob_destroyed"):
		Handlers.GameHandler.handle_fob_destroyed(owner_id)
	rpc("sync_fob_destroyed")
	queue_free()

@rpc("authority", "call_local", "reliable")
func sync_fob_destroyed() -> void:
	is_destroyed = true
	visible = false

### VISION ###

func _setup_vision_area() -> void:
	if visibility_area == null:
		return
	_apply_vision_shape_radius(vision_radius)
	visibility_area.body_entered.connect(_on_vision_body_entered)
	visibility_area.body_exited.connect(_on_vision_body_exited)
	visibility_area.monitoring = true

func _apply_vision_shape_radius(radius: float) -> void:
	var vis_shape: CollisionShape2D = visibility_area.get_node_or_null("VisibilityShape")
	if vis_shape == null or not vis_shape.shape is CircleShape2D:
		return
	var unique_circle := (vis_shape.shape as CircleShape2D).duplicate() as CircleShape2D
	unique_circle.radius = radius
	vis_shape.shape = unique_circle

func _refresh_existing_vision() -> void:
	if visibility_area == null:
		return
	for body in visibility_area.get_overlapping_bodies():
		_on_vision_body_entered(body)

func _on_vision_body_entered(body: Node2D) -> void:
	if not is_multiplayer_authority() or is_destroyed:
		return
	if not body is BaseUnitServer:
		return
	var unit := body as BaseUnitServer
	if not _is_enemy_unit(unit):
		return
	if unit not in has_vision_on:
		has_vision_on.append(unit)
	if unit not in _enemies_in_vision:
		_enemies_in_vision.append(unit)
	if unit not in unit.visible_by:
		unit.visible_by.append(self)

func _on_vision_body_exited(body: Node2D) -> void:
	if not is_multiplayer_authority():
		return
	if not body is BaseUnitServer:
		return
	var unit := body as BaseUnitServer
	if unit in has_vision_on:
		has_vision_on.erase(unit)
	if unit in _enemies_in_vision:
		_enemies_in_vision.erase(unit)
	if unit.visible_by.has(self):
		unit.visible_by.erase(self)

func _clear_vision_links() -> void:
	for unit in has_vision_on:
		if is_instance_valid(unit) and unit.visible_by.has(self):
			unit.visible_by.erase(self)
	has_vision_on.clear()
	_enemies_in_vision.clear()

func _is_enemy_unit(unit: BaseUnitServer) -> bool:
	if not is_instance_valid(unit):
		return false
	_resolve_owner_team()
	if owner_team != null and unit.owner_team != null:
		return owner_team != unit.owner_team
	if owner_id != 0 and unit.owner_id != 0:
		return owner_id != unit.owner_id
	return false

### СИСТЕМА ОТЛОЖЕННОГО СПАВНА ###

func _setup_spawn_timer() -> void:
	if not is_multiplayer_authority():
		return
	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)

func add_spawn_order(
		unit_type: String,
		unit_cost: int,
		player_id: int,
		spawn_delay: float = -1.0,
		preset_snapshot: Dictionary = {}
	) -> void:
	if not is_multiplayer_authority():
		return

	var resolved_delay := spawn_delay
	if resolved_delay < 0.0:
		resolved_delay = UNIT_SPAWN_DELAY
		if unit_type == "command_unit":
			resolved_delay = COMMAND_UNIT_SPAWN_DELAY

	var spawn_order = {
		"unit_type": unit_type,
		"unit_cost": unit_cost,
		"player_id": player_id,
		"spawn_delay": resolved_delay,
		"preset_snapshot": preset_snapshot,
	}
	spawn_queue.append(spawn_order)

	if spawn_queue.size() == 1:
		_start_next_spawn()
	else:
		_sync_spawn_ui_to_clients()

func _start_next_spawn() -> void:
	if spawn_queue.size() == 0:
		return
	var current_order = spawn_queue[0]
	spawn_timer.wait_time = current_order["spawn_delay"]
	spawn_timer.start()
	_sync_spawn_ui_to_clients()
	_start_ui_updates()

func _on_spawn_timer_timeout() -> void:
	if spawn_queue.size() == 0:
		return
	var current_order = spawn_queue[0]
	if Handlers.UnitSpawnHandler:
		Handlers.UnitSpawnHandler._internal_spawn_unit(
			global_position,
			current_order["unit_type"],
			current_order["player_id"],
			current_order.get("preset_snapshot", {})
		)
	spawn_queue.pop_front()
	_sync_spawn_ui_to_clients()
	if spawn_queue.size() > 0:
		_start_next_spawn()
	elif ui_update_timer:
		ui_update_timer.stop()

### UI УПРАВЛЕНИЕ СПАВНОМ ###

func _initialize_spawn_ui() -> void:
	if spawn_bar:
		spawn_bar.min_value = 0.0
		spawn_bar.max_value = 100.0
		spawn_bar.value = 0.0
		spawn_bar.visible = false
	if spawn_queue_label:
		spawn_queue_label.text = "0"
		spawn_queue_label.visible = false

func _update_spawn_ui_visibility() -> void:
	if is_multiplayer_authority():
		return
	var is_my_fob = false
	if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
		is_my_fob = (owner_id == Handlers.TeamHandler.my_profile.PlayerId)
	if not is_my_fob:
		if spawn_bar:
			spawn_bar.visible = false
		if spawn_queue_label:
			spawn_queue_label.visible = false

func server_reassign_owner(old_id: int, new_id: int) -> void:
	if not is_multiplayer_authority():
		return
	if owner_id == old_id:
		owner_id = new_id
	for order in spawn_queue:
		if int(order.get("player_id", 0)) == old_id:
			order["player_id"] = new_id


func _get_spawn_progress() -> float:
	var queue_size := spawn_queue.size()
	if queue_size == 0 or not spawn_timer or spawn_timer.time_left <= 0.0:
		return 0.0
	var current_order = spawn_queue[0]
	var spawn_delay: float = current_order["spawn_delay"]
	var elapsed_time := spawn_delay - spawn_timer.time_left
	return clamp((elapsed_time / spawn_delay) * 100.0, 0.0, 100.0)


func sync_spawn_ui_for_owner() -> void:
	if not is_multiplayer_authority():
		return
	_sync_spawn_ui_to_clients()


func _sync_spawn_ui_to_clients() -> void:
	if not is_multiplayer_authority():
		return
	var queue_size := spawn_queue.size()
	var current_progress := _get_spawn_progress()
	if owner_id == multiplayer.get_unique_id():
		_apply_spawn_ui(queue_size, current_progress)
	elif owner_id in multiplayer.get_peers():
		update_spawn_ui.rpc_id(owner_id, queue_size, current_progress)


func _apply_spawn_ui(queue_size: int, progress: float) -> void:
	if queue_size > 0:
		if spawn_queue_label:
			spawn_queue_label.text = str(queue_size)
			spawn_queue_label.visible = true
		if spawn_bar:
			spawn_bar.value = progress
			spawn_bar.visible = true
	else:
		if spawn_queue_label:
			spawn_queue_label.visible = false
		if spawn_bar:
			spawn_bar.visible = false


@rpc("any_peer", "reliable")
func update_spawn_ui(queue_size: int, progress: float) -> void:
	if multiplayer.is_server():
		return
	var is_my_fob := false
	if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
		is_my_fob = (owner_id == Handlers.TeamHandler.my_profile.PlayerId)
	if not is_my_fob:
		if spawn_bar:
			spawn_bar.visible = false
		if spawn_queue_label:
			spawn_queue_label.visible = false
		return
	_apply_spawn_ui(queue_size, progress)

func get_spawn_queue_size() -> int:
	return spawn_queue.size()

func _setup_ui_update_timer() -> void:
	if not is_multiplayer_authority():
		return
	ui_update_timer = Timer.new()
	ui_update_timer.wait_time = 0.1
	ui_update_timer.timeout.connect(_on_ui_update_timer_timeout)
	ui_update_timer.autostart = false
	add_child(ui_update_timer)

func _on_ui_update_timer_timeout() -> void:
	if spawn_queue.size() > 0 and spawn_timer and spawn_timer.time_left > 0.0:
		_sync_spawn_ui_to_clients()
	else:
		ui_update_timer.stop()

func _start_ui_updates() -> void:
	if ui_update_timer and ui_update_timer.time_left > 0.0:
		return
	if ui_update_timer and spawn_queue.size() > 0:
		ui_update_timer.start()
