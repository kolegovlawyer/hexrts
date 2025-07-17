extends BaseUnit
class_name CommandUnit

# TODO: Phase 2 - Заменить временное увеличение спрайта (1.25x) на специальный визуальный индикатор
# Временное решение: спрайт командного юнита увеличен в 1.25 раза в command_unit.tscn
# для визуального отличия от обычных юнитов

# Параметры захвата гексов
const CAPTURE_TIME: float = 5.0  # Время захвата гекса в секундах
const CHECK_INTERVAL: float = 1.0  # Проверка каждую секунду (60 фреймов при 60 FPS)

# Текущий гекс, на котором находится юнит
var current_hex = null
var check_timer: float = 0.0

func _ready() -> void:
	super._ready()
	print("🎖️ DEBUG: CommandUnit _ready вызван, owner_id=", owner_id, " owner_team=", owner_team)
	
	# Проверяем что owner_team корректно установлен
	if is_multiplayer_authority() and owner_id != 1:
		var player = Handlers.TeamHandler.find_player_by_id(owner_id)
		if player:
			var expected_team = player.Team
			if owner_team != expected_team:
				owner_team = expected_team
				print("🔧 DEBUG: Скорректирован owner_team с ", owner_team, " на ", expected_team, " для CommandUnit")
			else:
				print("✅ DEBUG: owner_team=", owner_team, " корректен для CommandUnit")
		else:
			print("❌ DEBUG: Не удалось найти игрока с owner_id=", owner_id)
	
	# TODO: Phase 2 - Добавить специфичные для командного юнита параметры
	# - Радиус захвата гексов
	# - Скорость захвата 
	# - Особые способности

# Функция для проверки текущего гекса
# TODO: Phase 2 - Реализовать логику захвата гексов
func check_current_hex() -> void:
	"""
	Проверяет гекс под юнитом и обновляет информацию о присутствии
	Вызывается каждую секунду на сервере
	"""
	print("🔍 DEBUG: check_current_hex вызвана для ", name, " в позиции ", global_position)
	
	if not Handlers.GameHandler:
		print("❌ DEBUG: GameHandler не найден в check_current_hex")
		return
		
	# Получаем гекс по текущей позиции юнита
	var hex = Handlers.GameHandler.get_hex_at_world_position(global_position)
	print("🗺️ DEBUG: get_hex_at_world_position вернул: ", hex)
	
	# Если юнит сменил гекс
	if hex != current_hex:
		print("🔄 DEBUG: Смена гекса с ", current_hex, " на ", hex)
		# Удаляем из предыдущего гекса
		if current_hex:
			current_hex.remove_command_unit(self)
		
		# Добавляем в новый гекс
		current_hex = hex
		if current_hex:
			current_hex.add_command_unit(self)
			print("🎖️ ПОЗИЦИЯ: Командный юнит ", name, " переместился на гекс ", current_hex.position)
	
	# Если юнит на гексе, проверяем возможность захвата
	if current_hex:
		var my_team_str = ""
		var hex_team_str = ""
		match owner_team:
			0: my_team_str = "A"
			1: my_team_str = "B"
			-1: my_team_str = "нейтральный"
			_: my_team_str = str(owner_team)
		match current_hex.team_owner:
			0: hex_team_str = "A"
			1: hex_team_str = "B"
			-1: hex_team_str = "нейтральный"
			_: hex_team_str = str(current_hex.team_owner)
		
		print("📍 DEBUG: На гексе ", current_hex.position, " моя команда=", my_team_str, " владелец гекса=", hex_team_str)
		
		if current_hex.can_be_captured_by_team(owner_team):
			if current_hex.capturing_team != owner_team:
				current_hex.start_capture(owner_team)
			print("🏁 ЗАХВАТ: Команда ", my_team_str, " захватывает гекс ", current_hex.position, " (", current_hex.capture_progress * 100, "%)")
		else:
			print("🚫 DEBUG: Гекс ", current_hex.position, " нельзя захватить командой ", my_team_str)
	else:
		print("❌ DEBUG: current_hex равен null - юнит не на гексе")

# Переопределяем _physics_process для системы захвата гексов
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Логика захвата работает только на сервере
	if not is_multiplayer_authority():
		return
	
	# DEBUG: Проверяем основные переменные
	if check_timer == 0.0:  # Выводим один раз при запуске
		var team_str = ""
		match owner_team:
			0: team_str = "A"
			1: team_str = "B"
			-1: team_str = "нейтральный"
			_: team_str = str(owner_team)
		print("🎖️ DEBUG: CommandUnit команда ", team_str, " (", owner_team, ") owner_id=", owner_id, " position=", global_position)
		if not Handlers.GameHandler:
			print("❌ DEBUG: GameHandler не найден!")
		elif Handlers.GameHandler.hexes_dict.size() == 0:
			print("❌ DEBUG: hexes_dict пуст! Система гексов не инициализирована.")
		else:
			print("✅ DEBUG: GameHandler найден, hexes_dict содержит ", Handlers.GameHandler.hexes_dict.size(), " гексов")
	
	# Обновляем таймер проверки гексов (каждую секунду)
	check_timer += delta
	if check_timer >= CHECK_INTERVAL:
		check_timer = 0.0
		print("⏰ DEBUG: Таймер проверки гексов сработал для ", name)
		check_current_hex()
	
	# Обновляем прогресс захвата если юнит захватывает гекс
	if current_hex and current_hex.capturing_team == owner_team:
		var capture_speed = 1.0 / CAPTURE_TIME  # Скорость захвата
		var capture_completed = current_hex.update_capture_progress(delta, capture_speed)
		
		if capture_completed:
			var team_str = ""
			match owner_team:
				0: team_str = "A"
				1: team_str = "B"
				-1: team_str = "нейтральный"
				_: team_str = str(owner_team)
			print("✅ ЗАХВАТ: Гекс ", current_hex.position, " захвачен командой ", team_str, " (", owner_team, ")!")
			# Обновляем визуал гекса в OverlayMap
			Handlers.GameHandler.update_hex_overlay(current_hex.position, current_hex.team_owner)

func _exit_tree() -> void:
	"""Очищаем ссылки при удалении юнита"""
	if current_hex:
		current_hex.remove_command_unit(self)
