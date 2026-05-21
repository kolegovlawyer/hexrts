extends Node
class_name DebugSystem

# Диагностика ботов. print через Handlers.dprint — при Remote Debug иначе фризы.
var debug_timer: Timer

func _ready() -> void:
	if not is_multiplayer_authority() or not Handlers.DEBUG_LOG_ENABLED:
		return
		
	debug_timer = Timer.new()
	debug_timer.wait_time = 20.0
	debug_timer.timeout.connect(_print_debug_summary)
	debug_timer.autostart = true
	add_child(debug_timer)
	
	Handlers.dprint("🔍 DEBUG: Система диагностики запущена")

func _print_debug_summary() -> void:
	if not Handlers.GameHandler:
		return
		
	Handlers.dprint("\n🔍 === ДИАГНОСТИКА СИСТЕМЫ ===")
	
	var bots = Handlers.GameHandler.active_bots
	Handlers.dprint("🤖 Активных ботов: %d" % bots.size())
	
	for bot in bots:
		Handlers.dprint("  - Бот %s (ID:%s, команда:%s)" % [bot.bot_name, bot.bot_id, int(bot.bot_team)])
		Handlers.dprint("    * Очки: %s" % _get_bot_points(bot.bot_id))
		Handlers.dprint("    * Юнитов: %s" % _count_bot_units(bot.bot_id))
		Handlers.dprint("    * FOB найден: %s" % (bot._find_bot_fob() != null))
	
	if Handlers.TeamHandler:
		Handlers.dprint("👥 Игроков в TeamHandler: %d" % Handlers.TeamHandler.players.size())
		for player in Handlers.TeamHandler.players:
			Handlers.dprint("  - ID:%s команда:%s" % [player.PlayerId, int(player.Team)])
	
	var all_units = get_tree().get_nodes_in_group("units")
	Handlers.dprint("⚔️ Всего юнитов: %d" % all_units.size())
	
	var team_0_units = 0
	var team_1_units = 0
	
	for unit in all_units:
		if unit.owner_team == 0:
			team_0_units += 1
		elif unit.owner_team == 1:
			team_1_units += 1
	
	Handlers.dprint("  - Команда 0: %d юнитов" % team_0_units)
	Handlers.dprint("  - Команда 1: %d юнитов" % team_1_units)
	Handlers.dprint("🔍 === КОНЕЦ ДИАГНОСТИКИ ===\n")

func _get_bot_points(bot_id: int) -> float:
	if Handlers.GameHandler and Handlers.GameHandler.player_points.has(bot_id):
		return Handlers.GameHandler.player_points[bot_id]["recruitment_points"]
	return 0.0

func _count_bot_units(bot_id: int) -> int:
	var count = 0
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if unit.owner_id == bot_id:
			count += 1
	return count
