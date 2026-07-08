class_name Bot extends Node

const Brain = preload("res://scripts/bot/bot_brain.gd")

## ИИ бота: КШМ захватывает гексы, бойцы прикреплены к своему КШМ.

const DECISION_INTERVAL: float = 2.0
const SPAWN_CHECK_INTERVAL: float = 1.0
const DEFENDERS_PER_COMMAND_UNIT: int = 2
const ALARM_HEX_RANGE: int = 3
const POWER_REBALANCE_WAIT_SEC: float = 3.0
const COMMAND_SHIELD_RETREAT_RATIO: float = 0.2
const PATROL_RADIUS: float = 200.0
const FIGHTER_REJOIN_DISTANCE: float = 80.0
const RETREAT_DISTANCE: float = 300.0
const FOB_ARRIVAL_DISTANCE: float = 120.0
const COMBAT_CONTACT_TIMEOUT_SEC: float = 4.0

const CMD_STATE_IDLE_AT_FOB := "idle_at_fob"
const CMD_STATE_EXPANDING := "expanding"
const CMD_STATE_RETREATING := "retreating"
const CMD_STATE_REGENERATING := "regenerating"

const FIGHTER_STATE_GUARD := "guard"
const FIGHTER_STATE_ALARM := "alarm_response"
const FIGHTER_STATE_COMBAT := "combat"
const FIGHTER_STATE_RETREAT_SHIELD := "retreat_shield"
const FIGHTER_STATE_RETREAT_POWER := "retreat_power"
const FIGHTER_STATE_RETURNING := "returning"

var bot_id: int
var bot_team: GameTypes.Teams
var bot_name: String

var bot_units: Array[BaseUnit] = []
var command_units: Array[BaseUnit] = []
var controlled_hexes: Array[Vector2i] = []

var assigned_defenders: Dictionary = {}
var fighter_assigned_cmd: Dictionary = {}
var unit_states: Dictionary = {}
var active_alarms: Array[Dictionary] = []
var pursuit_targets: Dictionary = {}
var power_rebalance_until: Dictionary = {}
var last_combat_contact: Dictionary = {}

var decision_timer: Timer
var spawn_timer: Timer

var _fighter_preset: UnitPreset
var _command_preset: UnitPreset


func _ready() -> void:
	add_to_group("bots")
	add_to_group("ai_players")
	_fighter_preset = UnitPreset.create_default()
	_command_preset = UnitPreset.create_command_default()
	_setup_timers()
	call_deferred("_initialize_strategy")


func initialize_bot(id: int, team: GameTypes.Teams, display_name: String) -> void:
	bot_id = id
	bot_team = team
	bot_name = display_name
	if not is_multiplayer_authority():
		Handlers.dprint("BOT ERROR: bot must run on server")
		queue_free()


func _setup_timers() -> void:
	decision_timer = Timer.new()
	decision_timer.wait_time = DECISION_INTERVAL
	decision_timer.timeout.connect(_make_strategic_decisions)
	decision_timer.autostart = true
	add_child(decision_timer)

	spawn_timer = Timer.new()
	spawn_timer.wait_time = SPAWN_CHECK_INTERVAL
	spawn_timer.timeout.connect(_check_spawn_opportunity)
	spawn_timer.autostart = true
	add_child(spawn_timer)


func _initialize_strategy() -> void:
	await get_tree().process_frame
	if _find_bot_fob():
		call_deferred("_attempt_initial_spawn")


func _make_strategic_decisions() -> void:
	if not is_multiplayer_authority():
		return
	_prune_invalid_bot_units()
	_update_bot_state()
	_cleanup_alarms()
	_update_assigned_defenders()
	_tick_command_units()
	_tick_fighters()
	_dispatch_alarm_responders()


func _update_bot_state() -> void:
	bot_units.clear()
	command_units.clear()
	for unit in get_tree().get_nodes_in_group("units"):
		if unit is BaseUnit and unit.owner_id == bot_id:
			bot_units.append(unit)
			if unit.is_command_unit():
				command_units.append(unit)
			if not unit_states.has(unit.UID):
				_register_spawned_unit(unit)
	_update_controlled_hexes()


func _register_spawned_unit(unit: BaseUnit) -> void:
	if unit.is_command_unit():
		unit_states[unit.UID] = CMD_STATE_IDLE_AT_FOB
		if not assigned_defenders.has(unit):
			assigned_defenders[unit] = []
	else:
		unit_states[unit.UID] = FIGHTER_STATE_GUARD
		_assign_fighter_to_command(unit)


func _assign_fighter_to_command(fighter: BaseUnit) -> void:
	if fighter_assigned_cmd.has(fighter.UID):
		return
	var best_cmd: BaseUnit = null
	var best_deficit := -1
	for command_unit in command_units:
		if not is_instance_valid(command_unit):
			continue
		if not assigned_defenders.has(command_unit):
			assigned_defenders[command_unit] = []
		var defenders: Array = assigned_defenders[command_unit]
		var deficit := DEFENDERS_PER_COMMAND_UNIT - defenders.size()
		if deficit > best_deficit:
			best_deficit = deficit
			best_cmd = command_unit
	if best_cmd == null and not command_units.is_empty():
		best_cmd = command_units[0]
	if best_cmd == null:
		return
	fighter_assigned_cmd[fighter.UID] = best_cmd
	var defenders_list: Array = assigned_defenders[best_cmd]
	if fighter not in defenders_list and defenders_list.size() < DEFENDERS_PER_COMMAND_UNIT:
		defenders_list.append(fighter)


func _update_assigned_defenders() -> void:
	for command_unit in command_units:
		if not is_instance_valid(command_unit):
			continue
		if not assigned_defenders.has(command_unit):
			assigned_defenders[command_unit] = []
		var defenders: Array = assigned_defenders[command_unit]
		defenders = defenders.filter(func(u): return is_instance_valid(u))
		assigned_defenders[command_unit] = defenders
		while defenders.size() < DEFENDERS_PER_COMMAND_UNIT:
			var candidate := _find_unassigned_fighter(defenders)
			if candidate == null:
				break
			defenders.append(candidate)
			fighter_assigned_cmd[candidate.UID] = command_unit


func _find_unassigned_fighter(exclude: Array) -> BaseUnit:
	for unit in bot_units:
		if not is_instance_valid(unit) or unit.is_command_unit():
			continue
		if unit in exclude:
			continue
		if not fighter_assigned_cmd.has(unit.UID):
			return unit
	return null


func _tick_command_units() -> void:
	for command_unit in command_units:
		if not is_instance_valid(command_unit):
			continue
		_tick_command_unit(command_unit)


func _tick_command_unit(command_unit: BaseUnit) -> void:
	var state: String = unit_states.get(command_unit.UID, CMD_STATE_IDLE_AT_FOB)
	var bot_fob_node := _find_bot_fob()
	var at_fob := bot_fob_node != null and command_unit.global_position.distance_to(bot_fob_node.global_position) <= FOB_ARRIVAL_DISTANCE

	if _command_has_pending_alarm(command_unit):
		if state == CMD_STATE_EXPANDING and _is_unit_idle(command_unit):
			_order_retreat_to_fob(command_unit)
			unit_states[command_unit.UID] = CMD_STATE_RETREATING
			return

	if state == CMD_STATE_RETREATING:
		if at_fob:
			unit_states[command_unit.UID] = CMD_STATE_REGENERATING
		return

	if state == CMD_STATE_REGENERATING:
		if command_unit.shield >= command_unit.max_shield and _is_unit_idle(command_unit):
			unit_states[command_unit.UID] = CMD_STATE_IDLE_AT_FOB
		return

	if at_fob and command_unit.shield < int(command_unit.max_shield * COMMAND_SHIELD_RETREAT_RATIO):
		unit_states[command_unit.UID] = CMD_STATE_REGENERATING
		return

	if _is_command_retreating(command_unit):
		unit_states[command_unit.UID] = CMD_STATE_RETREATING
		return

	if _is_unit_in_combat(command_unit):
		return

	if state == CMD_STATE_IDLE_AT_FOB or (state == CMD_STATE_EXPANDING and _is_unit_idle(command_unit)):
		var target_hex := _find_nearest_available_hex_for_unit(command_unit, [])
		if target_hex != Vector2i.MAX:
			_order_hex_capture(command_unit, target_hex)
			unit_states[command_unit.UID] = CMD_STATE_EXPANDING


func _tick_fighters() -> void:
	for unit in bot_units:
		if not is_instance_valid(unit) or unit.is_command_unit():
			continue
		_tick_fighter(unit)


func _tick_fighter(fighter: BaseUnit) -> void:
	var state: String = unit_states.get(fighter.UID, FIGHTER_STATE_GUARD)
	var enemies := Brain.get_visible_enemies(fighter, bot_team, bot_id)
	var allies := Brain.get_visible_allies(fighter, bot_team, bot_id)
	var assigned_cmd: BaseUnit = fighter_assigned_cmd.get(fighter.UID)

	if enemies.is_empty() and state == FIGHTER_STATE_COMBAT:
		if _combat_contact_expired(fighter):
			unit_states[fighter.UID] = FIGHTER_STATE_RETURNING
			pursuit_targets.erase(fighter.UID)
			state = FIGHTER_STATE_RETURNING

	if not enemies.is_empty():
		last_combat_contact[fighter.UID] = Time.get_ticks_msec() / 1000.0
		var ally_power := Brain.sum_power([fighter] + allies)
		var enemy_power := Brain.sum_power(enemies)
		if fighter.shield <= 0 and state != FIGHTER_STATE_RETREAT_SHIELD:
			unit_states[fighter.UID] = FIGHTER_STATE_RETREAT_SHIELD
			state = FIGHTER_STATE_RETREAT_SHIELD
		elif enemy_power > ally_power and state not in [FIGHTER_STATE_RETREAT_POWER, FIGHTER_STATE_RETREAT_SHIELD]:
			unit_states[fighter.UID] = FIGHTER_STATE_RETREAT_POWER
			state = FIGHTER_STATE_RETREAT_POWER
		elif state in [FIGHTER_STATE_GUARD, FIGHTER_STATE_ALARM, FIGHTER_STATE_RETURNING]:
			unit_states[fighter.UID] = FIGHTER_STATE_COMBAT
			state = FIGHTER_STATE_COMBAT

	match state:
		FIGHTER_STATE_GUARD:
			_tick_fighter_guard(fighter, assigned_cmd, enemies)
		FIGHTER_STATE_ALARM:
			_tick_fighter_alarm(fighter, enemies)
		FIGHTER_STATE_COMBAT:
			_tick_fighter_combat(fighter, enemies, allies)
		FIGHTER_STATE_RETREAT_SHIELD:
			_tick_fighter_retreat_shield(fighter, enemies, allies, assigned_cmd)
		FIGHTER_STATE_RETREAT_POWER:
			_tick_fighter_retreat_power(fighter, enemies, allies, assigned_cmd)
		FIGHTER_STATE_RETURNING:
			_tick_fighter_returning(fighter, assigned_cmd, enemies)


func _tick_fighter_guard(fighter: BaseUnit, assigned_cmd: BaseUnit, enemies: Array) -> void:
	if not enemies.is_empty() or _is_unit_in_combat(fighter):
		return
	if not _is_unit_idle(fighter):
		return
	if not is_instance_valid(assigned_cmd):
		return
	var defenders: Array = assigned_defenders.get(assigned_cmd, [])
	var slot := defenders.find(fighter)
	if slot < 0:
		slot = 0
	var angle := (float(slot) * PI) + (Time.get_ticks_msec() * 0.0001)
	var offset := Vector2(cos(angle), sin(angle)) * PATROL_RADIUS
	_order_unit_move(fighter, assigned_cmd.global_position + offset)


func _tick_fighter_alarm(fighter: BaseUnit, enemies: Array) -> void:
	if not enemies.is_empty():
		return
	var alarm := _get_alarm_for_fighter(fighter)
	if alarm.is_empty():
		unit_states[fighter.UID] = FIGHTER_STATE_RETURNING
		return
	if fighter.global_position.distance_to(alarm.world_pos) > FOB_ARRIVAL_DISTANCE:
		if _is_unit_idle(fighter) and not _is_unit_in_combat(fighter):
			_order_unit_move(fighter, alarm.world_pos)
		return
	var aggressor: BaseUnit = alarm.get("aggressor")
	if is_instance_valid(aggressor) and aggressor in fighter.has_vision_on:
		_try_order_attack(fighter, aggressor, Brain.get_visible_allies(fighter, bot_team, bot_id))
	elif _is_unit_idle(fighter):
		unit_states[fighter.UID] = FIGHTER_STATE_GUARD


func _tick_fighter_combat(fighter: BaseUnit, enemies: Array, allies: Array) -> void:
	if enemies.is_empty():
		return
	if _is_unit_in_combat(fighter):
		return
	var target := _select_priority_enemy(fighter, enemies)
	if target == null:
		return
	if power_rebalance_until.has(fighter.UID):
		var until: float = power_rebalance_until[fighter.UID]
		if Time.get_ticks_msec() / 1000.0 < until:
			return
		power_rebalance_until.erase(fighter.UID)
		if _combat_contact_expired(fighter):
			pursuit_targets[fighter.UID] = target
			_try_pursue_enemy(fighter, target)
			return
	_try_order_attack(fighter, target, allies)


func _tick_fighter_retreat_shield(fighter: BaseUnit, enemies: Array, allies: Array, _assigned_cmd: BaseUnit) -> void:
	if fighter.shield >= fighter.max_shield:
		unit_states[fighter.UID] = FIGHTER_STATE_RETURNING
		return
	var ally_power := Brain.sum_power([fighter] + allies)
	var enemy_power := Brain.sum_power(enemies)
	if not enemies.is_empty() and ally_power < enemy_power:
		_order_retreat_from_threat(fighter, _threat_center(enemies))
		return
	if enemies.is_empty() or ally_power >= enemy_power:
		unit_states[fighter.UID] = FIGHTER_STATE_RETURNING


func _tick_fighter_retreat_power(fighter: BaseUnit, enemies: Array, allies: Array, assigned_cmd: BaseUnit) -> void:
	var ally_power := Brain.sum_power([fighter] + allies)
	var enemy_power := Brain.sum_power(enemies)
	if enemies.is_empty() or ally_power >= enemy_power:
		power_rebalance_until[fighter.UID] = Time.get_ticks_msec() / 1000.0 + POWER_REBALANCE_WAIT_SEC
		unit_states[fighter.UID] = FIGHTER_STATE_COMBAT
		return
	if _is_unit_idle(fighter) or fighter.unit_state == BaseUnit.UNIT_STATES.MOVING:
		var anchor := Brain.find_nearest_friendly_hex(fighter.global_position, bot_team)
		if is_instance_valid(assigned_cmd):
			anchor = assigned_cmd.global_position
		var retreat_pos := Brain.find_retreat_position(fighter.global_position, _threat_center(enemies), RETREAT_DISTANCE)
		if Brain.is_on_friendly_hex(retreat_pos, bot_team):
			_order_unit_move(fighter, retreat_pos)
		else:
			_order_unit_move(fighter, anchor)


func _tick_fighter_returning(fighter: BaseUnit, assigned_cmd: BaseUnit, enemies: Array) -> void:
	if not enemies.is_empty():
		return
	if not is_instance_valid(assigned_cmd):
		unit_states[fighter.UID] = FIGHTER_STATE_GUARD
		return
	if fighter.global_position.distance_to(assigned_cmd.global_position) <= FIGHTER_REJOIN_DISTANCE:
		unit_states[fighter.UID] = FIGHTER_STATE_GUARD
		return
	if _is_unit_idle(fighter) and not _is_unit_in_combat(fighter):
		_order_unit_move(fighter, assigned_cmd.global_position)


func _dispatch_alarm_responders() -> void:
	for alarm in active_alarms:
		if alarm.get("dispatched", false):
			continue
		for fighter in bot_units:
			if not is_instance_valid(fighter) or fighter.is_command_unit():
				continue
			var state: String = unit_states.get(fighter.UID, FIGHTER_STATE_GUARD)
			if state != FIGHTER_STATE_GUARD:
				continue
			if not Brain.get_visible_enemies(fighter, bot_team, bot_id).is_empty():
				continue
			var fighter_hex := Brain.world_to_hex(fighter.global_position)
			var alarm_hex: Vector2i = alarm.hex_pos
			if fighter_hex == Vector2i.MAX or Brain.hex_distance(fighter_hex, alarm_hex) > ALARM_HEX_RANGE:
				continue
			unit_states[fighter.UID] = FIGHTER_STATE_ALARM
			_order_unit_move(fighter, alarm.world_pos)
		alarm["dispatched"] = true


func _on_unit_under_attack(attacker: BaseUnit, victim: BaseUnit) -> void:
	if not is_instance_valid(victim) or victim.owner_id != bot_id:
		return
	if victim.is_command_unit():
		unit_states[victim.UID] = CMD_STATE_RETREATING
		if victim.shield < int(victim.max_shield * COMMAND_SHIELD_RETREAT_RATIO):
			_mark_defenders_returning(victim)
		return
	var enemies := Brain.get_visible_enemies(victim, bot_team, bot_id)
	if enemies.is_empty():
		_raise_alarm(victim, attacker)
	else:
		unit_states[victim.UID] = FIGHTER_STATE_COMBAT
		last_combat_contact[victim.UID] = Time.get_ticks_msec() / 1000.0


func _on_attack_started(_attacker: BaseUnit, _target: BaseUnit) -> void:
	pass


func _on_unit_died(dead_unit: BaseUnit) -> void:
	if not is_instance_valid(dead_unit) or dead_unit.owner_id != bot_id:
		return
	unit_states.erase(dead_unit.UID)
	fighter_assigned_cmd.erase(dead_unit.UID)
	pursuit_targets.erase(dead_unit.UID)
	power_rebalance_until.erase(dead_unit.UID)
	last_combat_contact.erase(dead_unit.UID)
	for command_unit in assigned_defenders.keys():
		var defenders: Array = assigned_defenders[command_unit]
		if dead_unit in defenders:
			defenders.erase(dead_unit)
	if dead_unit in bot_units:
		bot_units.erase(dead_unit)
	if dead_unit in command_units:
		command_units.erase(dead_unit)
	if dead_unit.is_command_unit():
		assigned_defenders.erase(dead_unit)
		for uid in fighter_assigned_cmd.keys():
			if fighter_assigned_cmd[uid] == dead_unit:
				fighter_assigned_cmd.erase(uid)


func _raise_alarm(victim: BaseUnit, aggressor: BaseUnit) -> void:
	var assigned_cmd: BaseUnit = fighter_assigned_cmd.get(victim.UID)
	var hex_pos := Brain.world_to_hex(victim.global_position)
	active_alarms.append({
		"hex_pos": hex_pos,
		"world_pos": victim.global_position,
		"source_fighter": victim,
		"assigned_cmd": assigned_cmd,
		"aggressor": aggressor,
		"time": Time.get_ticks_msec() / 1000.0,
		"dispatched": false,
	})
	if is_instance_valid(assigned_cmd):
		if assigned_cmd in command_units:
			pass


func _cleanup_alarms() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var fresh: Array[Dictionary] = []
	for alarm in active_alarms:
		if now - float(alarm.get("time", 0.0)) > 30.0:
			continue
		var source: BaseUnit = alarm.get("source_fighter")
		if is_instance_valid(source) and unit_states.get(source.UID, "") == FIGHTER_STATE_COMBAT:
			continue
		fresh.append(alarm)
	active_alarms = fresh


func _check_spawn_opportunity() -> void:
	if not is_multiplayer_authority():
		return
	_prune_invalid_bot_units()
	var points := _get_bot_recruitment_points()
	var spawn_choice := _decide_unit_to_spawn(points)
	if spawn_choice == "":
		return
	_attempt_spawn_unit(spawn_choice)


func _attempt_initial_spawn() -> void:
	for i in range(10):
		await get_tree().create_timer(1.0).timeout
		if _get_bot_recruitment_points() >= _command_preset.get_cost():
			_attempt_spawn_unit("command_unit")
			return


func _decide_unit_to_spawn(points: float) -> String:
	if command_units.is_empty() and points >= _command_preset.get_cost():
		return "command_unit"
	var needed_fighters := command_units.size() * DEFENDERS_PER_COMMAND_UNIT
	var current_fighters := _count_fighters()
	if current_fighters < needed_fighters and points >= _fighter_preset.get_cost():
		return "base_unit"
	if command_units.size() < 2 and points >= _command_preset.get_cost():
		return "command_unit"
	if points >= _fighter_preset.get_cost():
		return "base_unit"
	return ""


func _count_fighters() -> int:
	var count := 0
	for unit in bot_units:
		if is_instance_valid(unit) and not unit.is_command_unit():
			count += 1
	return count


func _attempt_spawn_unit(unit_type: String) -> void:
	var bot_fob := _find_bot_fob()
	if bot_fob == null or not Handlers.GameHandler:
		return
	var preset := _command_preset if unit_type == "command_unit" else _fighter_preset
	var cost := preset.get_cost()
	if not Handlers.GameHandler.validate_unit_spawn(bot_id, cost):
		return
	bot_fob.add_spawn_order(
		unit_type,
		cost,
		bot_id,
		preset.get_spawn_time(),
		preset.to_spawn_snapshot()
	)


func _try_order_attack(fighter: BaseUnit, target: BaseUnit, allies: Array) -> void:
	if not Brain.is_enemy(target, bot_team, bot_id):
		return
	if Brain.has_allies_in_fire_lane(fighter, target, allies):
		return
	if is_multiplayer_authority():
		fighter.add_order(target.UID, true)
	else:
		fighter.rpc_id(1, "add_order", target.UID, true)


func _try_pursue_enemy(fighter: BaseUnit, target: BaseUnit) -> void:
	if not is_instance_valid(target):
		return
	var next_pos := target.global_position
	if not Brain.is_on_friendly_hex(next_pos, bot_team):
		unit_states[fighter.UID] = FIGHTER_STATE_RETURNING
		return
	if _is_unit_idle(fighter):
		_order_unit_move(fighter, next_pos)


func _select_priority_enemy(fighter: BaseUnit, enemies: Array) -> BaseUnit:
	var best: BaseUnit = null
	var best_dist := INF
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var dist := fighter.global_position.distance_squared_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best


func _threat_center(enemies: Array) -> Vector2:
	if enemies.is_empty():
		return Vector2.ZERO
	var center := Vector2.ZERO
	for enemy in enemies:
		if is_instance_valid(enemy):
			center += enemy.global_position
	return center / float(enemies.size())


func _order_retreat_from_threat(fighter: BaseUnit, threat_pos: Vector2) -> void:
	var retreat_pos := Brain.find_retreat_position(fighter.global_position, threat_pos, RETREAT_DISTANCE)
	if Brain.is_on_friendly_hex(retreat_pos, bot_team):
		_order_unit_move(fighter, retreat_pos)
	else:
		_order_unit_move(fighter, Brain.find_nearest_friendly_hex(fighter.global_position, bot_team))


func _order_retreat_to_fob(command_unit: BaseUnit) -> void:
	var bot_fob_node := _find_bot_fob()
	if bot_fob_node == null:
		return
	_order_unit_move(command_unit, bot_fob_node.global_position)
	_mark_defenders_returning(command_unit)


func _mark_defenders_returning(command_unit: BaseUnit) -> void:
	var defenders: Array = assigned_defenders.get(command_unit, [])
	for defender in defenders:
		if is_instance_valid(defender):
			unit_states[defender.UID] = FIGHTER_STATE_RETURNING


func _command_has_pending_alarm(command_unit: BaseUnit) -> bool:
	for alarm in active_alarms:
		if alarm.get("assigned_cmd") == command_unit:
			return true
	return false


func _get_alarm_for_fighter(fighter: BaseUnit) -> Dictionary:
	var nearest: Dictionary = {}
	var best_dist := INF
	var fighter_hex := Brain.world_to_hex(fighter.global_position)
	for alarm in active_alarms:
		var alarm_hex: Vector2i = alarm.hex_pos
		if fighter_hex == Vector2i.MAX:
			continue
		var dist := float(Brain.hex_distance(fighter_hex, alarm_hex))
		if dist <= ALARM_HEX_RANGE and dist < best_dist:
			best_dist = dist
			nearest = alarm
	return nearest


func _is_command_retreating(command_unit: BaseUnit) -> bool:
	if command_unit is CommandUnitServer:
		return (command_unit as CommandUnitServer).is_retreating
	return false


func _is_unit_in_combat(unit: BaseUnit) -> bool:
	return unit.unit_state in [BaseUnit.UNIT_STATES.ATTACKING, BaseUnit.UNIT_STATES.AUTO_ATTACKING]


func _is_unit_idle(unit: BaseUnit) -> bool:
	if not is_instance_valid(unit):
		return false
	return unit.orders.is_empty() and unit.unit_state == BaseUnit.UNIT_STATES.IDLE


func _combat_contact_expired(fighter: BaseUnit) -> bool:
	if not last_combat_contact.has(fighter.UID):
		return true
	return Time.get_ticks_msec() / 1000.0 - float(last_combat_contact[fighter.UID]) >= COMBAT_CONTACT_TIMEOUT_SEC


func _order_unit_move(unit: BaseUnit, world_position: Vector2) -> void:
	if is_multiplayer_authority():
		unit.add_order(world_position, true)
	else:
		unit.rpc_id(1, "add_order", world_position, true)


func _order_hex_capture(unit: BaseUnit, hex_position: Vector2i) -> void:
	if not Handlers.GameHandler or not Handlers.GameHandler.overlay_map:
		return
	var world_position := Brain.hex_to_world(hex_position)
	if unit.global_position.distance_to(world_position) < 40.0:
		return
	_order_unit_move(unit, world_position)


func _find_nearest_available_hex_for_unit(unit: BaseUnit, assigned_hexes: Array[Vector2i]) -> Vector2i:
	if not Handlers.GameHandler:
		return Vector2i.MAX
	var nearest_hex := Vector2i.MAX
	var min_distance := INF
	for hex_pos in Handlers.GameHandler.hexes_dict.keys():
		var hex = Handlers.GameHandler.hexes_dict[hex_pos]
		if hex.team_owner != -1 or hex_pos in assigned_hexes:
			continue
		var hex_world := Brain.hex_to_world(hex_pos)
		var distance := unit.global_position.distance_to(hex_world)
		if distance < min_distance:
			min_distance = distance
			nearest_hex = hex_pos
	return nearest_hex


func _find_bot_fob() -> Node:
	return Brain.find_fob_for_bot(bot_id, get_tree())


func _get_bot_recruitment_points() -> float:
	if not Handlers.GameHandler or not Handlers.GameHandler.player_points.has(bot_id):
		return 0.0
	return Handlers.GameHandler.player_points[bot_id]["recruitment_points"]


func _update_controlled_hexes() -> void:
	controlled_hexes.clear()
	if not Handlers.GameHandler:
		return
	var team_int := int(bot_team)
	for hex_pos in Handlers.GameHandler.hexes_dict.keys():
		var hex = Handlers.GameHandler.hexes_dict[hex_pos]
		if hex.team_owner == team_int:
			controlled_hexes.append(hex_pos)


func _prune_invalid_bot_units() -> void:
	var valid_units: Array[BaseUnit] = []
	for unit in bot_units:
		if is_instance_valid(unit):
			valid_units.append(unit)
	bot_units = valid_units
	var valid_cmds: Array[BaseUnit] = []
	for unit in command_units:
		if is_instance_valid(unit):
			valid_cmds.append(unit)
	command_units = valid_cmds
	for uid in unit_states.keys():
		if not _has_unit_with_uid(uid):
			unit_states.erase(uid)
	for uid in fighter_assigned_cmd.keys():
		if not _has_unit_with_uid(uid):
			fighter_assigned_cmd.erase(uid)


func _has_unit_with_uid(uid: String) -> bool:
	for unit in bot_units:
		if is_instance_valid(unit) and unit.UID == uid:
			return true
	return false


func _exit_tree() -> void:
	Handlers.dprint("BOT: ", bot_name, " shutdown")
