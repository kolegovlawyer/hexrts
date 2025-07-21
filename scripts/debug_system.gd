extends Node
class_name DebugSystem

# Простая система диагностики для ботов
# Показывает только важную информацию без спама

var debug_timer: Timer

func _ready() -> void:
	if not is_multiplayer_authority():
		return
		
	# Таймер диагностики каждые 10 секунд
	debug_timer = Timer.new()
	debug_timer.wait_time = 10.0
	debug_timer.timeout.connect(_print_debug_summary)
	debug_timer.autostart = true
	add_child(debug_timer)
	
	print("🔍 DEBUG: Система диагностики запущена")

func _print_debug_summary() -> void:
	"""
	Выводит краткую сводку состояния системы каждые 10 секунд
	"""
	if not Handlers.GameHandler:
		return
		
	print("\n🔍 === ДИАГНОСТИКА СИСТЕМЫ ===")
	
	# Проверяем ботов
	var bots = Handlers.GameHandler.active_bots
	print("🤖 Активных ботов: ", bots.size())
	
	for bot in bots:
		print("  - Бот ", bot.bot_name, " (ID:", bot.bot_id, ", команда:", int(bot.bot_team), ")")
		print("    * Очки: ", _get_bot_points(bot.bot_id))
		print("    * Юнитов: ", _count_bot_units(bot.bot_id))
		print("    * FOB найден: ", bot._find_bot_fob() != null)
	
	# Проверяем систему команд
	if Handlers.TeamHandler:
		print("👥 Игроков в TeamHandler: ", Handlers.TeamHandler.players.size())
		for player in Handlers.TeamHandler.players:
			print("  - ID:", player.PlayerId, " команда:", int(player.Team))
	
	# Проверяем юниты
	var all_units = get_tree().get_nodes_in_group("units")
	print("⚔️ Всего юнитов: ", all_units.size())
	
	var team_0_units = 0
	var team_1_units = 0
	
	for unit in all_units:
		if unit.owner_team == 0:
			team_0_units += 1
		elif unit.owner_team == 1:
			team_1_units += 1
	
	print("  - Команда 0: ", team_0_units, " юнитов")
	print("  - Команда 1: ", team_1_units, " юнитов")
	print("🔍 === КОНЕЦ ДИАГНОСТИКИ ===\n")

func _get_bot_points(bot_id: int) -> float:
	"""Получает очки бота"""
	if Handlers.GameHandler and Handlers.GameHandler.player_points.has(bot_id):
		return Handlers.GameHandler.player_points[bot_id]["recruitment_points"]
	return 0.0

func _count_bot_units(bot_id: int) -> int:
	"""Считает юниты бота"""
	var count = 0
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if unit.owner_id == bot_id:
			count += 1
	return count 