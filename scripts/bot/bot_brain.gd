class_name BotBrain
extends RefCounted

## Утилиты тактики бота без состояния.

const DEFAULT_EXPLOSION_RADIUS: float = 50.0
const FIRE_LANE_WIDTH: float = DEFAULT_EXPLOSION_RADIUS * 2.0


static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	return int(a.distance_to(b))


static func is_enemy(unit: BaseUnit, bot_team: GameTypes.Teams, bot_id: int) -> bool:
	if not is_instance_valid(unit):
		return false
	if unit.owner_team != null:
		return int(unit.owner_team) != int(bot_team)
	if unit.owner_id != 0:
		return unit.owner_id != bot_id
	return false


static func is_ally(unit: BaseUnit, bot_team: GameTypes.Teams, bot_id: int) -> bool:
	if not is_instance_valid(unit):
		return false
	return not is_enemy(unit, bot_team, bot_id)


static func get_unit_power(unit: BaseUnit) -> int:
	if not is_instance_valid(unit):
		return 0
	if unit.preset_cost > 0:
		return unit.preset_cost
	var is_command := unit.is_command_unit()
	var stats := {
		"health": _stat_from_vitals(unit.max_health, UnitPresetBalance.HEALTH_PER_STAT),
		"shield": _stat_from_vitals(unit.max_shield, UnitPresetBalance.SHIELD_PER_STAT),
		"damage": maxi(1, unit.damage),
		"speed": UnitPresetBalance.DEFAULT_STAT,
		"range": _stat_from_vision(unit.vision_radius),
	}
	return UnitPresetBalance.calculate_cost(stats, is_command)


static func _stat_from_vitals(value: int, per_stat: int) -> int:
	if per_stat <= 0:
		return UnitPresetBalance.DEFAULT_STAT
	return maxi(UnitPresetBalance.STAT_MIN, mini(UnitPresetBalance.STAT_MAX, int(value / float(per_stat))))


static func _stat_from_vision(radius: float) -> int:
	if radius <= 0.0:
		return UnitPresetBalance.DEFAULT_STAT
	return maxi(UnitPresetBalance.STAT_MIN, mini(UnitPresetBalance.STAT_MAX, int(round(radius / float(UnitPresetBalance.VISION_RADIUS_PER_STAT)))))


static func get_visible_enemies(unit: BaseUnit, bot_team: GameTypes.Teams, bot_id: int) -> Array[BaseUnit]:
	var result: Array[BaseUnit] = []
	if not is_instance_valid(unit) or unit.has_vision_on.is_empty():
		return result
	for visible_unit in unit.has_vision_on:
		if is_instance_valid(visible_unit) and is_enemy(visible_unit, bot_team, bot_id):
			result.append(visible_unit)
	return result


static func get_visible_allies(unit: BaseUnit, bot_team: GameTypes.Teams, bot_id: int) -> Array[BaseUnit]:
	var result: Array[BaseUnit] = []
	if not is_instance_valid(unit) or unit.has_vision_on.is_empty():
		return result
	for visible_unit in unit.has_vision_on:
		if visible_unit == unit:
			continue
		if is_instance_valid(visible_unit) and is_ally(visible_unit, bot_team, bot_id):
			result.append(visible_unit)
	return result


static func sum_power(units: Array) -> int:
	var total := 0
	for unit in units:
		if is_instance_valid(unit):
			total += get_unit_power(unit)
	return total


static func is_on_friendly_hex(world_pos: Vector2, bot_team: GameTypes.Teams) -> bool:
	if not Handlers.GameHandler:
		return false
	var hex = Handlers.GameHandler.get_hex_at_world_position(world_pos)
	if hex == null:
		return false
	return hex.team_owner == int(bot_team)


static func world_to_hex(world_pos: Vector2) -> Vector2i:
	if not Handlers.GameHandler:
		return Vector2i.MAX
	var hex = Handlers.GameHandler.get_hex_at_world_position(world_pos)
	if hex == null:
		return Vector2i.MAX
	return hex.position


static func hex_to_world(hex_pos: Vector2i) -> Vector2:
	if not Handlers.GameHandler or not Handlers.GameHandler.overlay_map:
		return Vector2.ZERO
	var local_pos := Handlers.GameHandler.overlay_map.map_to_local(hex_pos)
	return Handlers.GameHandler.overlay_map.to_global(local_pos)


static func find_fob_for_bot(bot_id: int, tree: SceneTree) -> Node:
	for fob_node in tree.get_nodes_in_group("fobs"):
		if fob_node.owner_id == bot_id:
			return fob_node
	return null


static func has_allies_in_fire_lane(
		shooter: BaseUnit,
		target: BaseUnit,
		allies: Array,
		explosion_radius: float = DEFAULT_EXPLOSION_RADIUS
	) -> bool:
	if not is_instance_valid(shooter) or not is_instance_valid(target):
		return false
	var start := shooter.global_position
	var end := target.global_position
	var segment := end - start
	var segment_len_sq := segment.length_squared()
	if segment_len_sq < 1.0:
		return false
	var lane_half_width := maxf(explosion_radius, FIRE_LANE_WIDTH * 0.5)
	for ally in allies:
		if not is_instance_valid(ally) or ally == shooter or ally == target:
			continue
		var to_ally: Vector2 = ally.global_position - start
		var t: float = to_ally.dot(segment) / segment_len_sq
		if t < 0.0 or t > 1.0:
			continue
		var closest: Vector2 = start + segment * t
		if ally.global_position.distance_to(closest) <= lane_half_width:
			return true
	return false


static func find_nearest_friendly_hex(world_pos: Vector2, bot_team: GameTypes.Teams) -> Vector2:
	if not Handlers.GameHandler:
		return world_pos
	var best_pos := world_pos
	var best_dist := INF
	var team_int := int(bot_team)
	for hex_pos in Handlers.GameHandler.hexes_dict.keys():
		var hex = Handlers.GameHandler.hexes_dict[hex_pos]
		if hex.team_owner != team_int:
			continue
		var hex_world := hex_to_world(hex_pos)
		var dist := world_pos.distance_squared_to(hex_world)
		if dist < best_dist:
			best_dist = dist
			best_pos = hex_world
	return best_pos


static func find_retreat_position(from_pos: Vector2, threat_pos: Vector2, distance: float) -> Vector2:
	if threat_pos == Vector2.ZERO:
		return from_pos
	var away := (from_pos - threat_pos).normalized()
	if away.length_squared() < 0.01:
		away = Vector2.LEFT
	return from_pos + away * distance
