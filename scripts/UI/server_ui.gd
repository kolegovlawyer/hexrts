class_name ServerUI extends Control

## СЕРВЕРНЫЙ UI ДЛЯ УПРАВЛЕНИЯ БОТАМИ
# Простой интерфейс администратора сервера для добавления/удаления ботов

@onready var add_bot_button = get_node("%AddBotButton")
@onready var team_option = get_node("%TeamOption")
@onready var bots_list = get_node("%BotsList")

# Счетчик для уникальных имен ботов
var bot_counter: int = 1

func _ready() -> void:
	print("🖥️ SERVER UI: Серверный UI инициализирован")
	
	# Проверяем что мы на сервере
	if not is_multiplayer_authority():
		print("⚠️ SERVER UI: UI показан не на сервере, скрываем")
		hide()
		return
	
	# Обновляем список ботов каждые 2 секунды
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.timeout.connect(_update_bots_list)
	timer.autostart = true
	add_child(timer)
	
	print("✅ SERVER UI: Серверный UI готов к работе")

func _on_add_bot_button_pressed() -> void:
	"""
	Обработчик нажатия кнопки добавления бота
	"""
	if not is_multiplayer_authority():
		print("❌ SERVER UI: Попытка добавить бота не на сервере!")
		return
	
	var selected_team = team_option.get_selected_id()
	var bot_name = "Bot_" + str(bot_counter)
	bot_counter += 1
	
	print("🤖 SERVER UI: Создание серверного бота:")
	print("  - Имя: ", bot_name)
	print("  - Команда: ", selected_team, " (", GameTypes.Teams.values()[selected_team], ")")
	
	_create_server_bot(bot_name, GameTypes.Teams.values()[selected_team])

func _create_server_bot(bot_name: String, team: GameTypes.Teams) -> void:
	"""
	Создает бота полностью на сервере
	"""
	print("🏭 SERVER UI: Создание серверного бота ", bot_name)
	
	# Создаем уникальный ID для бота (отрицательный чтобы не пересекаться с игроками)
	var bot_id = -(bot_counter + 1000)  # -1001, -1002, etc.
	
	# Создаем ИИ систему
	var bot_ai = preload("res://scripts/bot.gd").new()
	bot_ai.name = "ServerBot_" + bot_name
	
	# Добавляем в сцену игры
	if Handlers.GameHandler:
		Handlers.GameHandler.add_child(bot_ai)
		
		# Инициализируем бота
		bot_ai.initialize_bot(bot_id, team, bot_name)
		
		# Регистрируем в GameManager
		Handlers.GameHandler.register_bot(bot_ai)
		
		# Создаем и назначаем FOB для бота
		_assign_fob_to_bot(bot_ai, team)
		
		print("✅ SERVER UI: Серверный бот ", bot_name, " создан (ID: ", bot_id, ")")
		
	else:
		print("❌ SERVER UI: GameHandler не найден!")

func _assign_fob_to_bot(bot: Bot, team: GameTypes.Teams) -> void:
	"""
	Назначает FOB боту из доступных FOB команды
	"""
	var team_fob_group = "team_%d_fobs" % int(team)
	var team_fobs = get_tree().get_nodes_in_group(team_fob_group)
	
	print("🏭 SERVER UI: Поиск FOB для команды ", team, " в группе ", team_fob_group)
	print("  - Найдено FOB: ", team_fobs.size())
	
	# Находим первый свободный FOB
	for fob in team_fobs:
		if fob.owner_id == 0 or fob.owner_id == 2 or fob.owner_id == 3:  # Свободный или серверный FOB
			fob.owner_id = bot.bot_id
			print("✅ SERVER UI: FOB назначен боту ", bot.bot_name, " (ID: ", bot.bot_id, ")")
			return
	
	# Если свободных FOB нет, назначаем первый попавшийся
	if team_fobs.size() > 0:
		var fob = team_fobs[0]
		fob.owner_id = bot.bot_id
		print("⚠️ SERVER UI: Принудительно назначен FOB боту ", bot.bot_name, " (перезаписан owner_id)")
	else:
		print("❌ SERVER UI: Не найдено FOB для команды ", team)

func _update_bots_list() -> void:
	"""
	Обновляет список активных ботов в UI
	"""
	if not Handlers.GameHandler:
		return
	
	# Очищаем старый список
	for child in bots_list.get_children():
		child.queue_free()
	
	# Добавляем информацию о каждом боте
	for bot in Handlers.GameHandler.active_bots:
		var bot_info = Label.new()
		var team_name = "A" if bot.bot_team == GameTypes.Teams.TEAM_A else "B"
		var units_count = bot.bot_units.size()
		var cmd_units_count = bot.command_units.size()
		
		bot_info.text = "🤖 %s (Команда %s) - %d юнитов (%d командных)" % [bot.bot_name, team_name, units_count, cmd_units_count]
		bot_info.add_theme_color_override("font_color", Color.WHITE)
		
		# Добавляем кнопку удаления
		var bot_container = HBoxContainer.new()
		bot_container.add_child(bot_info)
		
		var remove_button = Button.new()
		remove_button.text = "❌"
		remove_button.custom_minimum_size = Vector2(30, 20)
		remove_button.pressed.connect(_remove_bot.bind(bot))
		bot_container.add_child(remove_button)
		
		bots_list.add_child(bot_container)

func _remove_bot(bot: Bot) -> void:
	"""
	Удаляет бота с сервера
	"""
	if not is_multiplayer_authority():
		return
	
	print("🗑️ SERVER UI: Удаление бота ", bot.bot_name)
	
	# Освобождаем FOB
	var fobs = get_tree().get_nodes_in_group("fobs")
	for fob in fobs:
		if fob.owner_id == bot.bot_id:
			fob.owner_id = 0  # Делаем свободным
			print("🏭 SERVER UI: FOB освобожден от бота ", bot.bot_name)
	
	# Удаляем всех юнитов бота
	for unit in bot.bot_units:
		if is_instance_valid(unit):
			unit.queue_free()
	
	# Удаляем из GameManager
	if Handlers.GameHandler:
		Handlers.GameHandler.unregister_bot(bot)
	
	# Удаляем самого бота
	bot.queue_free()
	
	print("✅ SERVER UI: Бот удален") 
