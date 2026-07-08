class_name BattleLogUI
extends RefCounted

const _HexCoordinatesScript := preload("res://scripts/game_system/hex_coordinates.gd")
const _BattleLogServiceScript := preload("res://scripts/game_system/battle_log_service.gd")

const COLOR_TIME := "#9a9a9a"
const COLOR_WARNING := "#e6a045"
const COLOR_DANGER := "#e05555"
const COLOR_SUCCESS := "#6ecf6e"
const COLOR_HEX := "#7ec8e3"
const COLOR_ENEMY := "#e08080"
const COLOR_UNIT := "#d0d0d0"


static func format_event(
		event_type: int,
		hex_tile: Vector2i,
		match_seconds: float,
		actor_name: String = ""
	) -> String:
	var hex_label := _HexCoordinatesScript.tile_to_label(hex_tile)
	var time_tag := "[color=%s][%s][/color] " % [COLOR_TIME, _format_match_time(match_seconds)]
	var unit_label := actor_name if actor_name != "" else "юнит"

	match event_type:
		_BattleLogServiceScript.Event.OWN_UNIT_ATTACKED:
			return (
				time_tag
				+ ("[color=%s]Вражеский юнит[/color] атакует " % COLOR_ENEMY)
				+ _unit_tag(unit_label)
				+ " на гексе "
				+ _hex_tag(hex_label)
			)
		_BattleLogServiceScript.Event.OWN_UNIT_DESTROYED:
			return (
				time_tag
				+ ("[color=%s]%s уничтожен[/color] на гексе " % [COLOR_DANGER, unit_label])
				+ _hex_tag(hex_label)
			)
		_BattleLogServiceScript.Event.NEUTRAL_HEX_CAPTURED:
			return (
				time_tag
				+ ("[color=%s]%s[/color] захватил нейтральный гекс " % [COLOR_SUCCESS, unit_label])
				+ _hex_tag(hex_label)
			)
		_BattleLogServiceScript.Event.OWN_HEX_LOST:
			return (
				time_tag
				+ ("[color=%s]Вражеский юнит[/color] захватил ваш гекс " % COLOR_WARNING)
				+ _hex_tag(hex_label)
			)
		_BattleLogServiceScript.Event.FOB_ATTACKED:
			return (
				time_tag
				+ ("[color=%s]Вражеский юнит[/color] атакует вашу базу на гексе " % COLOR_ENEMY)
				+ _hex_tag(hex_label)
			)
		_BattleLogServiceScript.Event.FOB_DESTROYED:
			return (
				time_tag
				+ ("[color=%s]Ваша база уничтожена[/color] на гексе " % COLOR_DANGER)
				+ _hex_tag(hex_label)
			)
		_BattleLogServiceScript.Event.OWN_UNIT_STUCK:
			return (
				time_tag
				+ ("[color=%s]%s застрял[/color] на гексе " % [COLOR_WARNING, unit_label])
				+ _hex_tag(hex_label)
				+ " и остановился"
			)
		_:
			return time_tag + "Неизвестное событие на гексе " + _hex_tag(hex_label)


static func _hex_tag(hex_label: String) -> String:
	return "[color=%s]%s[/color]" % [COLOR_HEX, hex_label]


static func _unit_tag(unit_label: String) -> String:
	return "[color=%s]%s[/color]" % [COLOR_UNIT, unit_label]


static func _format_match_time(match_seconds: float) -> String:
	var total_seconds := maxi(0, int(match_seconds))
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]
