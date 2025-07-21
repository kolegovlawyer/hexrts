extends BaseUnit
class_name CommandUnit

# TODO: Phase 2 - Заменить временное увеличение спрайта (1.25x) на специальный визуальный индикатор
# Временное решение: спрайт командного юнита увеличен в 1.25 раза в command_unit.tscn
# для визуального отличия от обычных юнитов

# Параметры захвата гексов
const CAPTURE_TIME: float = 5.0  # Время захвата гекса в секундах
const CHECK_INTERVAL: float = 1.0  # Проверка каждую секунду (60 фреймов при 60 FPS)

@onready var capture_progress_bar = get_node("%CaptureProgress")

# Текущий гекс, на котором находится юнит
var current_hex = null
var check_timer: float = 0.0
var is_capturing: bool = false  # Флаг активного захвата (серверная логика)

func _ready() -> void:
	super._ready()
	
	# КЛИЕНТСКАЯ ЛОГИКА: Управление прогресс-баром только у владельца
	if not is_multiplayer_authority():
		if capture_progress_bar:
			capture_progress_bar.hide()
			capture_progress_bar.value = 0.0
	
	print("🎖️ DEBUG: CommandUnit _ready вызван, owner_id=", owner_id, " owner_team=", owner_team)
	
	# СЕРВЕРНАЯ ЛОГИКА: Инициализация команды
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

func can_capture_while_in_state(state: int) -> bool:
	"""
	Определяет, может ли командный юнит захватывать территорию в данном состоянии
	Захват возможен во всех состояниях кроме движения
	"""
	match state:
		UNIT_STATES.IDLE:
			return true  # Неподвижен - может захватывать
		UNIT_STATES.MOVING:
			return false  # В движении - не может захватывать
		UNIT_STATES.ATTACKING:
			return true  # Атакует стоя на месте - может захватывать
		UNIT_STATES.AUTO_ATTACKING:
			return true  # Автоатака стоя на месте - может захватывать
		_:
			return false  # Неизвестное состояние - не рискуем

# Функция для проверки текущего гекса
func check_current_hex() -> void:
	"""
	Проверяет гекс под юнитом и обновляет информацию о присутствии
	Вызывается каждую секунду на сервере
	"""
	if not Handlers.GameHandler:
		return
		
	# Получаем гекс по текущей позиции юнита
	var hex = Handlers.GameHandler.get_hex_at_world_position(global_position)
	
	# Если юнит сменил гекс
	if hex != current_hex:
		# Останавливаем захват предыдущего гекса
		if current_hex and is_capturing:
			stop_capture("смена гекса")
		
		# Удаляем из предыдущего гекса
		if current_hex:
			current_hex.remove_command_unit(self)
		
		# Добавляем в новый гекс
		current_hex = hex
		if current_hex:
			current_hex.add_command_unit(self)
			# Логируем только смену гекса
			print("🎖️ ", name, " переместился на гекс ", current_hex.position)
	
	# Если юнит на гексе, проверяем возможность захвата
	if current_hex:
		
		# УЛУЧШЕННАЯ ЛОГИКА: Захват возможен во всех состояниях кроме движения
		if can_capture_while_in_state(unit_state) and current_hex.can_be_captured_by_team(owner_team):
			if current_hex.capturing_team != owner_team:
				start_capture()
		else:
			if not can_capture_while_in_state(unit_state):
				if is_capturing:
					stop_capture("нельзя захватывать в состоянии " + UNIT_STATES.keys()[unit_state])
	else:
		if is_capturing:
			stop_capture("юнит покинул гекс")

func start_capture() -> void:
	"""Начинает процесс захвата гекса (серверная логика)"""
	if not current_hex:
		return
		
	current_hex.start_capture(owner_team)
	is_capturing = true
	
	# Уведомляем клиентов о начале захвата
	rpc("client_start_capture_visual", current_hex.position)
	
	print("🎬 ЗАХВАТ: Начат захват гекса ", current_hex.position, " командой ", owner_team, " в состоянии ", UNIT_STATES.keys()[unit_state])

func stop_capture(reason: String = "") -> void:
	"""Останавливает процесс захвата гекса (серверная логика)"""
	if not is_capturing:
		return
		
	is_capturing = false
	
	# Уведомляем клиентов об остановке захвата
	rpc("client_stop_capture_visual")
	
	# Сбрасываем прогресс захвата в гексе
	if current_hex:
		current_hex.reset_capture()
	
	var reason_text = " (" + reason + ")" if reason != "" else ""
	print("⏹️ ЗАХВАТ: Захват остановлен" + reason_text)

@rpc("authority", "reliable")
func client_start_capture_visual(hex_position: Vector2i) -> void:
	"""Показывает прогресс-бар захвата у клиента-владельца"""
	# Показываем прогресс-бар только у владельца юнита
	if owner_id == multiplayer.get_unique_id() and capture_progress_bar:
		capture_progress_bar.show()
		capture_progress_bar.value = 0.0
		capture_progress_bar.max_value = 100.0
		print("🎬 ВИЗУАЛ: Прогресс-бар захвата показан для гекса ", hex_position)

@rpc("authority", "reliable")
func client_stop_capture_visual() -> void:
	"""Скрывает прогресс-бар захвата у клиента-владельца"""
	# Скрываем прогресс-бар только у владельца юнита
	if owner_id == multiplayer.get_unique_id() and capture_progress_bar:
		capture_progress_bar.hide()
		capture_progress_bar.value = 0.0
		print("⏹️ ВИЗУАЛ: Прогресс-бар захвата скрыт")

@rpc("authority", "unreliable")
func client_update_capture_progress(progress_percent: float) -> void:
	"""Обновляет прогресс захвата у клиента-владельца"""
	# Обновляем прогресс только у владельца юнита
	if owner_id == multiplayer.get_unique_id() and capture_progress_bar and capture_progress_bar.visible:
		capture_progress_bar.value = progress_percent
		
		# Отладочная информация только для значительных изменений
		var current_step = int(progress_percent / 20) * 20  # Каждые 20%
		var prev_step = int((progress_percent - 5) / 20) * 20
		if current_step != prev_step and current_step > 0:
			print("📊 ВИЗУАЛ: Прогресс захвата - ", int(progress_percent), "%")

# Переопределяем обработчики изменения состояния для управления захватом
func _unit_state_exit(state: int) -> void:
	"""Обработка выхода из состояния"""
	super._unit_state_exit(state)
	
	# При выходе из любого состояния где был разрешен захват, ничего не делаем
	# Захват будет проверен в новом состоянии

func _unit_state_enter(state: int) -> void:
	"""Обработка входа в состояние"""
	super._unit_state_enter(state)
	
	# При входе в состояние движения останавливаем захват
	if state == UNIT_STATES.MOVING and is_capturing:
		stop_capture("начало движения")
	
	# В остальных состояниях захват может продолжаться или начаться заново
	print("🎖️ STATE: CommandUnit в состоянии ", UNIT_STATES.keys()[state], ", захват ", ("разрешен" if can_capture_while_in_state(state) else "запрещен"))

# Переопределяем _physics_process для системы захвата гексов
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# СЕРВЕРНАЯ ЛОГИКА
	if is_multiplayer_authority():
		# Обновляем таймер проверки гексов (каждую секунду)
		check_timer += delta
		if check_timer >= CHECK_INTERVAL:
			check_timer = 0.0
			check_current_hex()
		
		# Обновляем прогресс захвата если юнит захватывает гекс
		if is_capturing and current_hex and current_hex.capturing_team == owner_team:
			var capture_speed = 1.0 / CAPTURE_TIME  # Скорость захвата
			var capture_completed = current_hex.update_capture_progress(delta, capture_speed)
			
			# Отправляем обновление прогресса клиентам
			var progress_percent = current_hex.capture_progress * 100.0
			rpc("client_update_capture_progress", progress_percent)
			
			if capture_completed:
				var team_str = ""
				match owner_team:
					0: team_str = "A"
					1: team_str = "B"
					-1: team_str = "нейтральный"
					_: team_str = str(owner_team)
				print("✅ ЗАХВАТ: Гекс ", current_hex.position, " захвачен командой ", team_str, " (", owner_team, ")!")
				
				# Завершаем захват
				is_capturing = false
				rpc("client_stop_capture_visual")
				
				# Обновляем визуал гекса в OverlayMap
				Handlers.GameHandler.update_hex_overlay(current_hex.position, current_hex.team_owner)

func _exit_tree() -> void:
	"""Очищаем ссылки при удалении юнита"""
	if current_hex:
		current_hex.remove_command_unit(self)
		
	# Останавливаем захват при удалении юнита
	if is_capturing:
		stop_capture("удаление юнита")
