class_name BattleLogService
extends Node

const _HexCoordinatesScript := preload("res://scripts/game_system/hex_coordinates.gd")

enum Event {
	OWN_UNIT_ATTACKED,
	OWN_UNIT_DESTROYED,
	NEUTRAL_HEX_CAPTURED,
	OWN_HEX_LOST,
	FOB_ATTACKED,
	FOB_DESTROYED,
}

const ENGAGEMENT_TIMEOUT := 8.0

var _game: GameManager = null
var _engagements: Dictionary = {}


func setup(game: GameManager) -> void:
	_game = game


func on_unit_damaged(victim: BaseUnitServer, attacker: BaseUnitServer) -> void:
	if _game == null or victim == null:
		return
	if not _game.is_multiplayer_authority():
		return
	if attacker == null or not is_instance_valid(attacker):
		return
	if _game._is_player_bot(victim.owner_id):
		return
	if not _should_log_engagement(_engagement_key(attacker.UID, victim.UID)):
		return

	var hex_tile := _world_to_hex_tile(victim.global_position)
	_send_to_player(victim.owner_id, Event.OWN_UNIT_ATTACKED, hex_tile)


func on_unit_died(victim: BaseUnitServer) -> void:
	if _game == null or victim == null:
		return
	if not _game.is_multiplayer_authority():
		return
	if _game._is_player_bot(victim.owner_id):
		return

	var hex_tile := _world_to_hex_tile(victim.global_position)
	_send_to_player(victim.owner_id, Event.OWN_UNIT_DESTROYED, hex_tile)


func on_fob_damaged(fob_node: fob, attacker: BaseUnitServer) -> void:
	if _game == null or fob_node == null:
		return
	if not _game.is_multiplayer_authority():
		return
	if attacker == null or not is_instance_valid(attacker):
		return
	if _game._is_player_bot(fob_node.owner_id):
		return
	if not _should_log_engagement(_engagement_key(attacker.UID, "fob:%s" % fob_node.UID)):
		return

	var hex_tile := _world_to_hex_tile(fob_node.global_position)
	_send_to_player(fob_node.owner_id, Event.FOB_ATTACKED, hex_tile)


func on_fob_destroyed(fob_node: fob) -> void:
	if _game == null or fob_node == null:
		return
	if not _game.is_multiplayer_authority():
		return
	if _game._is_player_bot(fob_node.owner_id):
		return

	var hex_tile := _world_to_hex_tile(fob_node.global_position)
	_send_to_player(fob_node.owner_id, Event.FOB_DESTROYED, hex_tile)


func on_hex_captured(
		hex_tile: Vector2i,
		old_owner: int,
		new_owner: int,
		capturer: BaseUnitServer
	) -> void:
	if _game == null:
		return
	if not _game.is_multiplayer_authority():
		return

	if capturer != null and is_instance_valid(capturer):
		if old_owner == -1 and not _game._is_player_bot(capturer.owner_id):
			_send_to_player(capturer.owner_id, Event.NEUTRAL_HEX_CAPTURED, hex_tile)

	if old_owner >= 0 and new_owner >= 0 and old_owner != new_owner:
		for player_id in _game._get_human_players_on_team(old_owner):
			if not _player_has_vision_at(player_id, hex_tile):
				continue
			_send_to_player(player_id, Event.OWN_HEX_LOST, hex_tile)


func _engagement_key(attacker_uid: String, victim_uid: String) -> String:
	return "%s|%s" % [attacker_uid, victim_uid]


func _should_log_engagement(key: String) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if _engagements.has(key):
		var started_at: float = _engagements[key]
		if now - started_at <= ENGAGEMENT_TIMEOUT:
			return false
	_engagements[key] = now
	return true


func _world_to_hex_tile(world_position: Vector2) -> Vector2i:
	if _game == null:
		return Vector2i.ZERO
	var hex = _game.get_hex_at_world_position(world_position)
	if hex:
		return hex.position
	if _game.overlay_map:
		var local_position := _game.overlay_map.to_local(world_position)
		return _game.overlay_map.local_to_map(local_position)
	return Vector2i.ZERO


func _player_has_vision_at(player_id: int, hex_tile: Vector2i) -> bool:
	if _game == null or _game.overlay_map == null:
		return false

	var world_pos := _game.overlay_map.to_global(
		_game.overlay_map.map_to_local(hex_tile) + Vector2(_game.overlay_map.tile_set.tile_size) * 0.5
	)

	for unit in _game.units_dict.values():
		if not is_instance_valid(unit):
			continue
		if unit.owner_id != player_id:
			continue
		var radius: float = unit.vision_radius
		if unit.global_position.distance_squared_to(world_pos) <= radius * radius:
			return true

	for fob_node in _game.fobs_dict.values():
		if not is_instance_valid(fob_node):
			continue
		if fob_node.owner_id != player_id:
			continue
		var fob_radius: float = fob_node.vision_radius
		if fob_node.global_position.distance_squared_to(world_pos) <= fob_radius * fob_radius:
			return true

	return false


func _send_to_player(player_id: int, event_type: int, hex_tile: Vector2i) -> void:
	if _game == null or _game._is_player_bot(player_id):
		return

	if _game._is_local_human_player(player_id):
		if Handlers.UIHandler:
			Handlers.UIHandler.append_battle_log_event(event_type, hex_tile, _game.match_elapsed_seconds)
	elif _game._is_connected_remote_peer(player_id):
		_game.rpc_battle_log_event.rpc_id(
			player_id, event_type, hex_tile, _game.match_elapsed_seconds
		)
