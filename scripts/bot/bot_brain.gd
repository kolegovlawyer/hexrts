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


static func is_navigable_world_position(world_pos: Vector2) -> bool:
	if not Handlers.GameHandler:
		return false
	return Handlers.GameHandler.get_hex_at_world_position(world_pos) != null


static func find_nearest_navigable_world_position(
		from_pos: Vector2,
		preferred_pos: Vector2,
		bot_team: GameTypes.Teams
	) -> Vector2:
	if is_navigable_world_position(preferred_pos):
		return preferred_pos
	if not Handlers.GameHandler:
		return preferred_pos
	var best_pos := from_pos
	var best_dist := preferred_pos.distance_squared_to(from_pos)
	var team_int := int(bot_team)
	for hex_pos in Handlers.GameHandler.hexes_dict.keys():
		var hex = Handlers.GameHandler.hexes_dict[hex_pos]
		if hex.team_owner != team_int and hex.team_owner != -1:
			continue
		var hex_world := hex_to_world(hex_pos)
		var dist := hex_world.distance_squared_to(preferred_pos)
		if dist < best_dist:
			best_dist = dist
			best_pos = hex_world
	return best_pos


static func find_guard_patrol_position(
		anchor_pos: Vector2,
		slot: int,
		bot_team: GameTypes.Teams,
		max_hex_radius: int = 2
	) -> Vector2:
	var anchor_hex := world_to_hex(anchor_pos)
	if anchor_hex == Vector2i.MAX:
		return anchor_pos
	var candidates: Array[Vector2i] = []
	var team_int := int(bot_team)
	for hex_pos in Handlers.GameHandler.hexes_dict.keys():
		var hex = Handlers.GameHandler.hexes_dict[hex_pos]
		if hex.team_owner != team_int:
			continue
		var dist: int = hex_distance(hex_pos, anchor_hex)
		if dist == 0 or dist > max_hex_radius:
			continue
		candidates.append(hex_pos)
	if candidates.is_empty():
		return anchor_pos
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return hex_distance(a, anchor_hex) < hex_distance(b, anchor_hex)
	)
	return hex_to_world(candidates[slot % candidates.size()])


static func find_artillery_deploy_position(
		from_pos: Vector2,
		alarm_pos: Vector2,
		attack_range: float,
		bot_team: GameTypes.Teams
	) -> Vector2:
	var friendly_anchor := find_nearest_friendly_hex(alarm_pos, bot_team)
	var to_friendly := friendly_anchor - alarm_pos
	if to_friendly.length_squared() < 1.0:
		to_friendly = from_pos - alarm_pos
	if to_friendly.length_squared() < 1.0:
		to_friendly = Vector2.LEFT
	var direction := to_friendly.normalized()
	var deploy_distance := minf(attack_range, to_friendly.length())
	if deploy_distance < 40.0:
		deploy_distance = minf(attack_range, 120.0)
	var deploy_pos := alarm_pos + direction * deploy_distance
	if is_on_friendly_hex(deploy_pos, bot_team):
		return deploy_pos
	return find_nearest_friendly_hex(deploy_pos, bot_team)
