class_name BaseUnitServer extends BaseUnit

### СЕРВЕРНАЯ ЛОГИКА ЮНИТА
# Содержит только серверные вычисления: навигация, атаки, движение, ИИ
# Коммуницирует с клиентской частью через RPC

const SPEED = 300.0

@onready var collision = get_node("%CollisionShape2D")
@onready var synchronizer = get_node("%MultiplayerSynchronizer")
@onready var visibility_area = get_node("%VisibilityArea")
@onready var reload_timer = get_node("%ReloadTimer")
@onready var aim_timer = get_node("%AimTimer")

# Таймер для автоматической атаки (проверка каждую секунду)
var auto_attack_timer: Timer

# Таймер для восстановления щита
var shield_regeneration_timer: Timer

@onready var navagent : NavigationAgent2D = $NavigationAgent2D
var path_points : Array[Vector2] = []

# DEBUG (логи через Handlers.dprint, DEBUG_LOG_ENABLED в handlers.gd)
var DEBUG_COMBAT: bool = false

# Кэши без set_meta / аллокаций строк на горячих путях
var _visibility_state_cached: bool = false
var _last_enemy_visibility: bool = false
var _last_enemy_visibility_valid: bool = false
var _last_visibility_update_frame: int = -100
var _team_resolve_error_logged: bool = false
var _can_see_target_uid: String = ""
var _can_see_result: bool = false
var _can_see_frame: int = -100
var _enemies_in_vision: Array[BaseUnitServer] = []

# Флаг для отложенной инициализации команды (когда setter вызван до добавления в дерево)
var _pending_team_initialization: bool = false

func _initialize_team_and_visibility() -> void:
	"""
	Инициализирует команду юнита и настраивает видимость
	Вызывается из setter'а owner_id или из _ready() при отложенной инициализации
	"""
	if not is_multiplayer_authority():
		return
	
	synchronizer.owner_id = owner_id
	
	# Безопасно получаем команду для серверных ботов и обычных игроков
	var bot_team = _get_bot_team_by_id(owner_id)
	if bot_team != -1:
		# Это бот
		owner_team = bot_team
		Handlers.dprint("🤖 TEAM INIT: %s - бот, команда = %s" % [name, owner_team])
	else:
		# Это обычный игрок
		var player = Handlers.TeamHandler.find_player_by_id(owner_id)
		if player:
			owner_team = player.Team
			Handlers.dprint("👤 TEAM INIT: %s - игрок, команда = %s" % [name, owner_team])
		else:
			Handlers.dprint("⚠️ TEAM INIT: %s - игрок не найден! owner_id = %s" % [name, owner_id])
			return
	
	update_visibility()

### Характеристики, которые должны заполняться из unit_profile
			
var accel = 7
@export var speed = 300
@export var damage = 5
@export var reload_time = 3
@export var shield_regen_rate = 1.5  # Щит в секунду при восстановлении (15/10 = 1.5)
@export var shield_regen_delay = 3.0  # Задержка начала восстановления щита после получения урона

var _health = 30
var _shield = 15

var frame_group : int

# Профилирующие функции для отслеживания производительности
var _profile_data: Dictionary = {}
var _last_attack_state: String = ""
var _attack_count: int = 0

func _profile_function_start(function_name: String) -> void:
	"""Начинает профилирование функции"""
	if not _profile_data.has(function_name):
		_profile_data[function_name] = {"calls": 0, "total_time": 0.0, "max_time": 0.0}
	
	_profile_data[function_name]["start_time"] = Time.get_ticks_usec() / 1000000.0

func _profile_function_end(function_name: String) -> void:
	"""Завершает профилирование функции"""
	if not _profile_data.has(function_name):
		return
	
	var end_time = Time.get_ticks_usec() / 1000000.0
	var start_time = _profile_data[function_name].get("start_time", end_time)
	var duration = end_time - start_time
	
	_profile_data[function_name]["calls"] += 1
	_profile_data[function_name]["total_time"] += duration
	_profile_data[function_name]["max_time"] = max(_profile_data[function_name]["max_time"], duration)

func get_profile_stats() -> Dictionary:
	"""Возвращает статистику профилирования"""
	return _profile_data.duplicate(true)

func log_profile_stats() -> void:
	"""Выводит статистику профилирования в консоль"""
	Handlers.dprint("=== ПРОФИЛЬ ПРОИЗВОДИТЕЛЬНОСТИ ЮНИТА %s ===" % name)
	for func_name in _profile_data.keys():
		var data = _profile_data[func_name]
		var avg_time = data["total_time"] / data["calls"] if data["calls"] > 0 else 0
		Handlers.dprint("  %s: %d вызовов, среднее: %s с, макс: %s с" % [func_name, data["calls"], avg_time, data["max_time"]])
	Handlers.dprint("=== КОНЕЦ ПРОФИЛЯ ===")

# Добавляем переменные для контроля застревания
var stuck_timer: float = 0.0
var last_move_position: Vector2 = Vector2.ZERO

func generate_numeric_id(length: int) -> String:
	var id := ""
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	for i in range(length):
		id += str(rng.randi_range(0, 9))
	return id

func _ready() -> void:
	# Вызываем базовый _ready()
	super._ready()
	
	# ИСПРАВЛЕНИЕ: Выполняем отложенную инициализацию команды если нужно
	if _pending_team_initialization:
		_pending_team_initialization = false
		_initialize_team_and_visibility()
	
	# Отладочная сводка по коллизиям/команде
	if is_multiplayer_authority() and DEBUG_COMBAT:
		Handlers.dprint("🧩 UNIT READY: %s UID=%s owner_id=%s team=%s" % [name, UID, owner_id, owner_team])
	
	# Создаем таймер автоматической атаки (только на сервере)
	if is_multiplayer_authority():
		_setup_auto_attack_timer()
		_setup_shield_regeneration_timer()
		# ИСПРАВЛЕНИЕ: Инициализируем frame_group для тяжелых вычислений
		if Handlers.FrameGroupHandler:
			frame_group = Handlers.FrameGroupHandler.add_to_framegroup(self)
			Handlers.dprint("🔧 FRAMEGROUP: %s группа %d" % [name, frame_group])
		else:
			frame_group = randi() % 60
			Handlers.dprint("⚠️ FRAMEGROUP: %s случайная группа %d (handler недоступен)" % [name, frame_group])
	
	if is_multiplayer_authority():
		UID = str(generate_numeric_id(10))
		# Регистрируем серверный юнит для корректных ссылок и поиска
		if not is_in_group("units"):
			add_to_group("units")
		if Handlers.GameHandler and Handlers.GameHandler.has_method("get"):
			if not Handlers.GameHandler.units_dict.has(UID):
				Handlers.GameHandler.units_dict[UID] = self
		if Handlers.GameHandler and Handlers.GameHandler.has_method("register_new_unit"):
			Handlers.GameHandler.register_new_unit(self)
		navagent.connect("velocity_computed", on_velocity_computed)
		_set_navigation_avoidance(false)
		visibility_area.connect("body_entered", visibility_check_in)
		visibility_area.connect("body_exited", visibility_check_out)
		
		if owner_id != 1 and owner_team == null:
			_initialize_team_and_visibility()
		
		if owner_id != 1:
			call_deferred("_start_auto_attack_delayed")
			call_deferred("_fix_visibility_after_init")
	else:
		visibility_area.monitoring = false
		visibility_area.monitorable = false
	
	last_move_position = global_position
	
func _exit_tree() -> void:
	# Безопасная очистка регистрации при удалении из дерева
	if Handlers.GameHandler and Handlers.GameHandler.has_method("get"):
		if Handlers.GameHandler.units_dict.has(UID):
			Handlers.GameHandler.units_dict.erase(UID)
	if is_in_group("units"):
		remove_from_group("units")
	
func visibility_check_in(body) -> void:
	"""Быстрая проверка входа в зону видимости"""
	if body == self or not body is BaseUnitServer:
		return
	
	if not has_vision_on.has(body):
		has_vision_on.append(body)
	if not body.visible_by.has(self):
		body.visible_by.append(self)
	
	var my_team = _get_cached_team()
	if my_team != null and _is_enemy_unit_fast(body, my_team) and body not in _enemies_in_vision:
		_enemies_in_vision.append(body)
	
func visibility_check_out(body) -> void:
	"""Быстрая проверка выхода из зоны видимости"""
	if body == self or not body is BaseUnitServer:
		return
	
	if has_vision_on.has(body):
		has_vision_on.erase(body)
	if body.visible_by.has(self):
		body.visible_by.erase(self)
	if body in _enemies_in_vision:
		_enemies_in_vision.erase(body)
	
func on_velocity_computed(safe_velocity):
	velocity = safe_velocity

func is_time_to_heavy_calculations() -> bool:
	if not Handlers.FrameGroupHandler or Handlers.FrameGroupHandler.num_groups <= 0:
		return false
	
	return (Engine.get_physics_frames() % Handlers.FrameGroupHandler.num_groups) == frame_group

func _physics_process(delta: float) -> void:
	_profile_function_start("_physics_process")
	
	if is_multiplayer_authority():
		
		# === ЛЕГКИЕ ВЫЧИСЛЕНИЯ (КАЖДЫЙ ФРЕЙМ - МГНОВЕННАЯ РЕАКЦИЯ) ===
		# Быстрая локальная проверка видимости (без сетевых операций)
		_quick_visibility_check()
		
		# ⚡ КРИТИЧЕСКИ ВАЖНО: Обработка приказов ТОЛЬКО ИГРОКОВ мгновенно!
		var _is_bot = _get_bot_team_by_id(owner_id) != -1
		if not _is_bot and orders.size() > 0:
			var order = orders[0]
			match order.type:
				"move":
					_process_move_order_immediate(order, delta, _is_bot)
				"attack":
					_process_attack_order_immediate(order)
		
		# ИСПРАВЛЕНИЕ: Обработка приказов атаки в состоянии AUTO_ATTACKING (автоатака ИИ)
		# Для автоатаки нужно обрабатывать приказы в каждом фрейме для отзывчивости
		if unit_state == UNIT_STATES.AUTO_ATTACKING and orders.size() > 0:
			var attack_order = orders[0]
			if attack_order.type == "attack":
				_process_attack_order_immediate(attack_order)
		
		# Движение (только если navagent не завершен)
		if not navagent.is_navigation_finished():
			var current_unit_position = global_position
			var next_path_position = navagent.get_next_path_position()
			velocity = current_unit_position.direction_to(next_path_position)*speed
			move_and_slide()
		
		# === ТЯЖЕЛЫЕ ВЫЧИСЛЕНИЯ (РАСПРЕДЕЛЕННЫЕ ПО ФРЕЙМАМ - АВТОМАТИКА) ===
		if is_time_to_heavy_calculations():
			_process_heavy_server_calculations(delta)
	
	_profile_function_end("_physics_process")

func _process_move_order_immediate(order: Dictionary, delta: float, is_bot: bool) -> void:
	"""МГНОВЕННАЯ обработка приказов движения для отзывчивости игрока"""
	# Переключаемся в состояние движения
	if unit_state != UNIT_STATES.MOVING:
		unit_state = UNIT_STATES.MOVING
	
	var pos = order.position
	navagent.target_position = pos
	
	# УЛУЧШЕННАЯ НАВИГАЦИЯ: Проверяем доступность и используем альтернативы
	if not navagent.is_target_reachable():
		# Цель недоступна - используем систему умных альтернатив
		var alternative_target = _find_alternative_path_target(pos)
		navagent.target_position = alternative_target
	
	# Увеличенный порог для ботов (проблема малых расстояний!)
	var distance_to_target = global_position.distance_to(pos)
	var close_enough_threshold = 24.0 if is_bot else 12.0  # Оптимизированные пороги
	var close_enough = distance_to_target < close_enough_threshold
	var nav_done = navagent.is_navigation_finished()
	var moved = global_position.distance_to(last_move_position) > 1.5  # Чувствительность к движению
	
	if close_enough or nav_done:
		orders.pop_front()
		unit_state = UNIT_STATES.IDLE
		stuck_timer = 0.0
	elif not moved:
		stuck_timer += delta
		if stuck_timer > 2.5:  # Быстрее реагируем на застревание
			# УЛУЧШЕННАЯ СИСТЕМА ОБХОДА ЗАСТРЕВАНИЯ
			_execute_smart_unstuck_maneuver(pos)
			stuck_timer = 0.0  # Сбрасываем таймер
	else:
		stuck_timer = 0.0
	last_move_position = global_position

func _process_attack_order_immediate(order: Dictionary) -> void:
	"""МГНОВЕННАЯ обработка приказов атаки для отзывчивости игрока"""
	# Переключаемся в состояние атаки
	if unit_state != UNIT_STATES.ATTACKING and unit_state != UNIT_STATES.AUTO_ATTACKING:
		unit_state = UNIT_STATES.ATTACKING
	
	# Безопасная проверка цели
	if not is_instance_valid(order.target):
		orders.pop_front()
		unit_state = UNIT_STATES.IDLE
	else:
		var target: BaseUnitServer = order.target
		# Проверяем видимость цели
		if not can_see_target(target):
			orders.pop_front()
			unit_state = UNIT_STATES.IDLE
		else:
			# Атакуем мгновенно!
			attack(target)

func _quick_visibility_check() -> void:
	"""
	БЫСТРАЯ проверка видимости без сетевых операций
	Только локальные флаги, тяжелые сетевые операции в FrameGroup
	"""
	# Проверяем видимость ИМЕННО для врагов: если хотя бы один вражеский юнит видит нас
	var currently_visible: bool = false
	var my_team = _get_cached_team()
	if my_team != null:
		for viewer in visible_by:
			if is_instance_valid(viewer) and _is_enemy_unit_fast(viewer, my_team):
				currently_visible = true
				break
	else:
		# Если команда пока неизвестна, осторожно считаем что враги нас не видят
		currently_visible = false
	
	_visibility_state_cached = currently_visible

func _process_heavy_server_calculations(delta: float) -> void:
	"""
	ПЕРЕРАБОТАНО: Тяжелые серверные вычисления для АВТОМАТИЧЕСКИХ систем и БОТОВ
	Включает: обработку приказов ботов, автоатаку ИИ, сложные проверки видимости, отладку
	ИСКЛЮЧЕНО: обработка приказов игроков (мгновенная!)
	"""
	_profile_function_start("_process_heavy_server_calculations")
	
	var is_bot = _get_bot_team_by_id(owner_id) != -1
	
	# === ТЯЖЕЛЫЕ СЕТЕВЫЕ ОПЕРАЦИИ ВИДИМОСТИ ===
	_process_visibility_heavy()
	
	# === ОБРАБОТКА ПРИКАЗОВ БОТОВ (ОТЛОЖЕННАЯ) ===
	if is_bot and orders.size() > 0:
		var bot_order = orders[0]
		match bot_order.type:
			"move":
				_process_move_order_heavy_bot(bot_order, delta)
			"attack":
				_process_attack_order_heavy_bot(bot_order)
	# === АВТОАТАКА (ПОИСК ЦЕЛЕЙ) - ТОЛЬКО ЕСЛИ НЕТ ПРИКАЗОВ ===
	elif orders.size() == 0:
		_process_auto_attack_heavy()
	
	_profile_function_end("_process_heavy_server_calculations")

func _process_visibility_heavy() -> void:
	"""
	Тяжелые сетевые операции видимости, выполняемые через FrameGroup
	"""
	set_visibility_for_enemy(_visibility_state_cached)

func _process_move_order_heavy_bot(order: Dictionary, delta: float) -> void:
	"""ОТЛОЖЕННАЯ обработка приказов движения для БОТОВ (FrameGroup оптимизация)"""
	# Переключаемся в состояние движения
	if unit_state != UNIT_STATES.MOVING:
		unit_state = UNIT_STATES.MOVING
	
	var pos = order.position
	navagent.target_position = pos
	
	# УЛУЧШЕННАЯ НАВИГАЦИЯ: Проверяем доступность и используем альтернативы
	if not navagent.is_target_reachable():
		# Цель недоступна - используем систему умных альтернатив
		var alternative_target = _find_alternative_path_target(pos)
		navagent.target_position = alternative_target
	
	# Увеличенный порог для ботов (проблема малых расстояний!)
	var distance_to_target = global_position.distance_to(pos)
	var close_enough_threshold = 32.0  # Ботам нужен больший порог
	var close_enough = distance_to_target < close_enough_threshold
	var nav_done = navagent.is_navigation_finished()
	var moved = global_position.distance_to(last_move_position) > 1.5
	
	if close_enough or nav_done:
		orders.pop_front()
		unit_state = UNIT_STATES.IDLE
		stuck_timer = 0.0
	elif not moved:
		stuck_timer += delta
		if stuck_timer > 3.0:  # Ботам можно дать больше времени
			_execute_smart_unstuck_maneuver(pos)
			stuck_timer = 0.0
	else:
		stuck_timer = 0.0
	last_move_position = global_position

func _process_attack_order_heavy_bot(order: Dictionary) -> void:
	"""ОТЛОЖЕННАЯ обработка приказов атаки для БОТОВ (FrameGroup оптимизация)"""
	# Переключаемся в состояние атаки
	if unit_state != UNIT_STATES.ATTACKING and unit_state != UNIT_STATES.AUTO_ATTACKING:
		unit_state = UNIT_STATES.ATTACKING
	
	# Безопасная проверка цели
	if not is_instance_valid(order.target):
		orders.pop_front()
		unit_state = UNIT_STATES.IDLE
	else:
		var target: BaseUnitServer = order.target
		# Проверяем видимость цели
		if not can_see_target(target):
			orders.pop_front()
			unit_state = UNIT_STATES.IDLE
		else:
			# Атакуем через FrameGroup оптимизацию
			attack(target)

func _process_auto_attack_heavy() -> void:
	"""Тяжелый поиск целей для автоатаки"""
	# Нет приказов - переходим в состояние ожидания для автоатаки
	if unit_state != UNIT_STATES.IDLE and unit_state != UNIT_STATES.AUTO_ATTACKING:
		unit_state = UNIT_STATES.IDLE
	
	# Поиск целей для автоатаки (только в состоянии IDLE)
	if unit_state == UNIT_STATES.IDLE:
		var visible_enemies = _get_visible_enemies()
		
		# DEBUG: Логирование для диагностики атаки
		if not visible_enemies.is_empty():
			var target_enemy = _select_best_target(visible_enemies)
			if is_valid_unit(target_enemy):
				if DEBUG_COMBAT:
					Handlers.dprint("🎯 ATTACK: %s -> %s" % [name, target_enemy.name])
				orders.append({"type": "attack", "target": target_enemy})
				unit_state = UNIT_STATES.AUTO_ATTACKING

@rpc("any_peer", "reliable")
func add_order(order_obj, clear_queue:bool=false) -> void:
	# Проверка владельца: обычные игроки или сервер для ботов
	var sender_id = multiplayer.get_remote_sender_id()
	var is_bot = _get_bot_team_by_id(owner_id) != -1
	
	# Для прямых вызовов от ботов на сервере - разрешаем без проверки sender_id
	if is_bot and is_multiplayer_authority():
		# Прямой вызов разрешен
		pass
	elif not (owner_id == sender_id or (is_bot and sender_id == 1)):
		return
	
	if is_multiplayer_authority():
		match typeof(order_obj):
			TYPE_VECTOR2:
				# Приказ на движение
				if clear_queue:
					orders.clear()
				orders.append({"type": "move", "position": order_obj})
			TYPE_STRING:
				# Приказ на атаку по имени
				var target_unit = find_target_by_UID(order_obj)
				if target_unit is BaseUnitServer:
					# Проверяем видимость цели перед добавлением приказа
					if can_see_target(target_unit):
						if clear_queue:
							orders.clear()
						orders.append({"type": "attack", "target": target_unit})

@rpc("any_peer", "reliable")
func get_unit_info() -> void:
	"""Возвращает информацию о юните через RPC"""
	var sender_id = multiplayer.get_remote_sender_id()
	if is_multiplayer_authority() and unit_profile:
		rpc_id(sender_id, "set_unit_info", unit_profile.resource_path)	

@rpc("any_peer", "reliable")
func clear_orders() -> void:
	"""
	Очищает все приказы юнита и переводит его в состояние ожидания
	Вызывается при снятии выделения с юнита
	"""
	if owner_id != multiplayer.get_remote_sender_id():
		return
		
	if is_multiplayer_authority():
		orders.clear()
		# Переводим юнит в состояние ожидания для автоатаки
		unit_state = UNIT_STATES.IDLE

func find_target_by_UID(target_uid: String) -> BaseUnitServer:
	# Ищем юнит по UID в дереве сцены
	if Handlers.GameHandler and Handlers.GameHandler.has_method("get") and Handlers.GameHandler.units_dict.has(target_uid):
		var target = Handlers.GameHandler.units_dict[target_uid]
		if target:
			return target
	
	# Альтернативный поиск через группы
	var units = get_tree().get_nodes_in_group("units")
	for unit in units:
		if unit.has_method("get") and unit.get("UID") == target_uid:
			return unit
	
	return null

@rpc("authority", "reliable")
func rpc_apply_damage_to_uid(target_uid: String, amount: int, instigator_uid: String = "") -> void:
	"""
	Авторитетный RPC: применяет урон к юниту по его UID.
	Используется снарядами/системами урона, чтобы не зависеть от прямых ссылок.
	"""
	if not is_multiplayer_authority():
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	var target: BaseUnitServer = find_target_by_UID(target_uid)
	if not is_valid_unit(target):
		if DEBUG_COMBAT:
			Handlers.dprint("❌ RPC DMG: target not found uid=%s sender=%s" % [target_uid, sender_id])
		return
	
	var instigator: BaseUnitServer = null
	if instigator_uid != "":
		instigator = find_target_by_UID(instigator_uid)
	
	# Friendly-fire фильтр с логом (не наносим урон союзникам, если команды известны)
	if is_valid_unit(instigator) and instigator.owner_team != null and target.owner_team != null and instigator.owner_team == target.owner_team:
		if DEBUG_COMBAT:
			Handlers.dprint("🛡️ RPC DMG BLOCKED (FF): %s -> %s" % [instigator.name, target.name])
		return
	
	if DEBUG_COMBAT:
		var inst_name = instigator.name if is_valid_unit(instigator) else "null"
		Handlers.dprint("✅ RPC DMG: %d -> %s inst=%s" % [amount, target.name, inst_name])
	
	target.apply_damage(amount, instigator)

@rpc("authority", "reliable")
func rpc_apply_aoe_damage(center: Vector2, radius: float, amount: int, instigator_uid: String = "") -> void:
	"""
	Авторитетный RPC: наносит AoE-урон всем валидным юнитам в радиусе.
	Оптимизировано: сравнение через distance_squared.
	"""
	if not is_multiplayer_authority():
		return
	
	var radius_sq: float = radius * radius
	var instigator: BaseUnitServer = null
	if instigator_uid != "":
		instigator = find_target_by_UID(instigator_uid)
	
	var units = get_tree().get_nodes_in_group("units")
	for unit in units:
		if unit is BaseUnitServer and unit != null and is_instance_valid(unit):
			var d2 = center.distance_squared_to(unit.global_position)
			if d2 <= radius_sq:
				# FF фильтр с логом
				if is_valid_unit(instigator) and instigator.owner_team != null and unit.owner_team != null and instigator.owner_team == unit.owner_team:
					if DEBUG_COMBAT:
						Handlers.dprint("🛡️ AOE DMG SKIP (FF): %s -> %s" % [instigator.name, unit.name])
					continue
				
				if DEBUG_COMBAT:
					var inst_name = instigator.name if is_valid_unit(instigator) else "null"
					Handlers.dprint("🌊 AOE DMG: %d -> %s inst=%s" % [amount, unit.name, inst_name])
				unit.apply_damage(amount, instigator)

func can_see_target(target: BaseUnitServer) -> bool:
	"""Проверяет, может ли юнит видеть указанную цель (кэш на 3 физ. кадра)."""
	if not is_instance_valid(target):
		return false
	
	var current_frame := Engine.get_physics_frames()
	if target.UID == _can_see_target_uid and current_frame - _can_see_frame < 3:
		return _can_see_result
	
	var can_see := false
	if _get_bot_team_by_id(owner_id) != -1:
		can_see = global_position.distance_squared_to(target.global_position) <= 160000.0
	else:
		can_see = has_vision_on.has(target)
	
	_can_see_target_uid = target.UID
	_can_see_result = can_see
	_can_see_frame = current_frame
	return can_see
	
func attack(target: BaseUnitServer) -> void:
	_profile_function_start("attack")
	
	# Дополнительная проверка валидности цели
	if not is_instance_valid(target):
		if DEBUG_COMBAT:
			Handlers.dprint("❌ ATTACK CANCELLED: target invalid for %s" % name)
		_profile_function_end("attack")
		return
	
	# Проверка видимости цели
	if not can_see_target(target):
		# Удаляем приказ атаки, так как цель невидима
		if orders.size() > 0 and orders[0].type == "attack":
			orders.pop_front()
		if DEBUG_COMBAT:
			Handlers.dprint("👁️ ATTACK BLOCKED (no vision): %s -> %s" % [name, target.name])
		_profile_function_end("attack")
		return
		
	var current_state: String
	
	if reload_timer.time_left > 0:
		current_state = "cooldown"
		if _last_attack_state != current_state:
			_last_attack_state = current_state
		_profile_function_end("attack")
		return
	
	current_state = "ready"
	if _last_attack_state != current_state:
		if _last_attack_state == "cooldown":
			pass
		else:
			pass
		_last_attack_state = current_state
		_attack_count = 0
	
	# Испускаем сигнал для системы ботов (начало атаки)
	attack_started.emit(self, target)
	
	# Делегируем создание снаряда централизованной системе ProjectileSystem
	if Handlers.ProjectileHandler:
		var explosion_radius = 50.0  # Радиус взрыва (можно сделать настраиваемым параметром юнита)
		if DEBUG_COMBAT:
			Handlers.dprint("🚀 PROJECTILE: %s -> %s dmg=%d" % [name, target.name, damage])
		Handlers.ProjectileHandler.rpc("create_projectile", UID, target.UID, damage, explosion_radius)
	else:
		if DEBUG_COMBAT:
			Handlers.dprint("⚠️ PROJECTILE HANDLER MISSING: %s" % name)
	
	reload_timer.wait_time = reload_time  # Убеждаемся, что используется правильное время
	reload_timer.start()
	
	_last_attack_state = "fired"
	_profile_function_end("attack")

func apply_damage(amount: int, from: BaseUnitServer = null) -> void:
	"""
	Наносит урон юниту с учетом щита
	
	ЛОГИКА УРОНА:
	1. Сначала урон поглощается щитом
	2. Излишки урона наносятся здоровью
	3. Останавливается восстановление щита
	
	ПАРАМЕТРЫ:
	- amount: Количество урона
	- from: Источник урона (может быть null если источник был уничтожен)
	"""
	# Испускаем сигнал для системы ботов о том, что юнит подвергается атаке
	if from and is_instance_valid(from):
		under_attack.emit(from, self)
	
	if DEBUG_COMBAT:
		var instigator_name = from.name if from and is_instance_valid(from) else "null"
		Handlers.dprint("💥 APPLY DAMAGE: %s <= %d from=%s" % [name, amount, instigator_name])
	
	var remaining_damage = amount
	
	# Сначала урон поглощается щитом
	if _shield > 0:
		var shield_damage: int = min(_shield, remaining_damage)
		# ВАЖНО: обновляем бэкинг-поле напрямую на сервере
		_shield = max(_shield - shield_damage, 0)
		remaining_damage -= shield_damage
		
		# Останавливаем восстановление щита и сбрасываем таймер
		if is_multiplayer_authority() and shield_regeneration_timer:
			shield_regeneration_timer.stop()
			# Перезапускаем таймер задержки восстановления
			shield_regeneration_timer.wait_time = shield_regen_delay
			shield_regeneration_timer.start()
	
	# Оставшийся урон наносится здоровью
	if remaining_damage > 0:
		# ВАЖНО: обновляем бэкинг-поле напрямую на сервере
		_health = max(_health - remaining_damage, 0)
	
	# Синхронизируем клиентам актуальные значения через RPC (для обновления баров)
	rpc("sync_health", _health)
	rpc("sync_shield", _shield)
	
	if DEBUG_COMBAT:
		Handlers.dprint("🧮 AFTER DAMAGE: %s hp=%d/%d sh=%d/%d" % [name, _health, max_health, _shield, max_shield])
	
	# Проверяем смерть по серверному значению
	if _health <= 0:
		die()

func sync_health(new_health_value: int) -> void:
	"""
	Синхронизирует значение здоровья между сервером и клиентами
	Вызывается только с сервера при изменении здоровья
	"""
	if not is_multiplayer_authority():
		_health = new_health_value

func sync_shield(new_shield_value: int) -> void:
	"""
	Синхронизирует значение щита между сервером и клиентами
	Вызывается только с сервера при изменении щита
	"""
	if not is_multiplayer_authority():
		_shield = new_shield_value

func die() -> void:
	unit_died.emit(self)
	
	var observers: Array[BaseUnit] = []
	for viewer in visible_by:
		if is_instance_valid(viewer) and viewer not in observers:
			observers.append(viewer)
	for seen in has_vision_on:
		if is_instance_valid(seen) and seen not in observers:
			observers.append(seen)
	
	visible_by.clear()
	has_vision_on.clear()
	_enemies_in_vision.clear()
	
	for observer in observers:
		if observer.has_method("_on_unit_died"):
			observer._on_unit_died(self)
	# Снимаем регистрацию из словаря и групп
	if Handlers.GameHandler and Handlers.GameHandler.has_method("get"):
		if Handlers.GameHandler.units_dict.has(UID):
			Handlers.GameHandler.units_dict.erase(UID)
	if is_in_group("units"):
		remove_from_group("units")
	queue_free()

func _on_unit_died(dead_unit: BaseUnit) -> void:
	if dead_unit in visible_by:
		visible_by.erase(dead_unit)
	if dead_unit in has_vision_on:
		has_vision_on.erase(dead_unit)
	if dead_unit is BaseUnitServer and dead_unit in _enemies_in_vision:
		_enemies_in_vision.erase(dead_unit)

# === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ РЕФАКТОРИНГА ===
func is_valid_unit(unit) -> bool:
	"""Проверяет, что объект существует и является BaseUnitServer"""
	return unit != null and is_instance_valid(unit) and unit is BaseUnitServer

func update_visibility():
	"""ОПТИМИЗИРОВАНО: Обновление видимости с кэшированием"""
	if not is_multiplayer_authority():
		return
	
	var current_frame := Engine.get_physics_frames()
	if current_frame - _last_visibility_update_frame < 10:
		return
	_last_visibility_update_frame = current_frame
	
	# Быстрое определение команды с кэшированием
	var unit_team = _get_cached_team()
	if unit_team == null:
		return
	
	# ИСПРАВЛЕНИЕ: Получаем список активных peer'ов
	var active_peers = multiplayer.get_peers()
	
	# Сначала скрываем юнит от ВСЕХ игроков (только активных)
	for player_id in active_peers:
		_safe_set_visibility(player_id, false)
	
	# Затем показываем только союзникам
	var team_players = Handlers.TeamHandler.get_team_players(unit_team)
	if team_players:
		for player in team_players:
			# Проверяем что peer активен перед установкой видимости
			if player.PlayerId in active_peers:
				_safe_set_visibility(player.PlayerId, true)

func _get_cached_team():
	"""ОПТИМИЗАЦИЯ: Кэшированное получение команды юнита"""
	if owner_team != null:
		return owner_team
	
	# Пытаемся определить команду если она не задана
	var bot_team = _get_bot_team_by_id(owner_id)
	if bot_team != -1:
		owner_team = bot_team
		return owner_team
	else:
		var player = Handlers.TeamHandler.find_player_by_id(owner_id)
		if player:
			owner_team = player.Team
			return owner_team
		else:
			_team_resolve_error_logged = true
			return null

func _safe_set_visibility(peer_id: int, is_visible_flag: bool) -> void:
	"""
	Безопасно устанавливает видимость для peer'а с проверкой существования
	"""
	# Проверяем что peer существует и synchronizer валидный
	if not is_instance_valid(synchronizer):
		return
	
	# Дополнительная проверка существования peer'а
	var active_peers = multiplayer.get_peers()
	if peer_id not in active_peers and peer_id != 1:  # 1 - это сервер
		return
	
	# Устанавливаем видимость
	synchronizer.set_visibility_for(peer_id, is_visible_flag)
			
func set_visibility_for_enemy(is_visible_flag: bool) -> void:
	"""ОПТИМИЗИРОВАНО: Установка видимости для врагов с кэшированием"""
	if not is_multiplayer_authority():
		return
	
	if _last_enemy_visibility_valid and _last_enemy_visibility == is_visible_flag:
		return
	_last_enemy_visibility = is_visible_flag
	_last_enemy_visibility_valid = true
	
	# Быстрое определение команды с кэшированием
	var unit_team = _get_cached_team()
	if unit_team == null:
		return
	
	# ИСПРАВЛЕНИЕ: Безопасное установление видимости для врагов
	var enemy_players = Handlers.TeamHandler.get_enemy_team_players(unit_team)
	var active_peers = multiplayer.get_peers()
	
	if enemy_players:
		for player in enemy_players:
			# Проверяем что enemy peer активен
			if player.PlayerId in active_peers:
				_safe_set_visibility(player.PlayerId, is_visible_flag)

## СИСТЕМА СОСТОЯНИЙ (STATE MACHINE)
func _set_navigation_avoidance(enabled: bool) -> void:
	if navagent and navagent.avoidance_enabled != enabled:
		navagent.avoidance_enabled = enabled

func _unit_state_exit(state: int) -> void:
	"""
	Выход из состояния - очистка и завершение текущих действий
	"""
	match state:
		UNIT_STATES.IDLE:
			# При выходе из состояния ожидания особых действий не требуется
			pass
		UNIT_STATES.MOVING:
			# При выходе из движения можем остановить навигацию если нужно
			pass
		UNIT_STATES.ATTACKING:
			# При выходе из атаки можем прервать текущую атаку если нужно
			pass
		UNIT_STATES.AUTO_ATTACKING:
			# При выходе из автоатаки останавливаем таймер поиска целей
			if auto_attack_timer:
				auto_attack_timer.stop()

func _unit_state_enter(state: int) -> void:
	"""
	Вход в состояние - инициализация поведения
	"""
	match state:
		UNIT_STATES.IDLE:
			_set_navigation_avoidance(false)
			if auto_attack_timer and is_multiplayer_authority():
				auto_attack_timer.start()
			# В состоянии ожидания начинаем восстановление щита (если щит не полный)
			if shield_regeneration_timer and is_multiplayer_authority() and _shield < max_shield:
				shield_regeneration_timer.wait_time = shield_regen_delay
				shield_regeneration_timer.start()
		UNIT_STATES.MOVING:
			_set_navigation_avoidance(true)
			if auto_attack_timer:
				auto_attack_timer.stop()
			if shield_regeneration_timer and is_multiplayer_authority():
				shield_regeneration_timer.stop()
		UNIT_STATES.ATTACKING:
			_set_navigation_avoidance(false)
			if auto_attack_timer:
				auto_attack_timer.stop()
			if shield_regeneration_timer and is_multiplayer_authority():
				shield_regeneration_timer.stop()
		UNIT_STATES.AUTO_ATTACKING:
			_set_navigation_avoidance(false)
			if auto_attack_timer and is_multiplayer_authority():
				auto_attack_timer.start()
			if shield_regeneration_timer and is_multiplayer_authority():
				shield_regeneration_timer.stop()

## СИСТЕМА АВТОМАТИЧЕСКОЙ АТАКИ
func _setup_auto_attack_timer() -> void:
	"""
	Создает и настраивает таймер автоматической атаки
	Вызывается только на сервере при инициализации юнита
	"""
	auto_attack_timer = Timer.new()
	auto_attack_timer.wait_time = 1.0  # Проверка каждую секунду
	auto_attack_timer.timeout.connect(_on_auto_attack_timer_timeout)
	auto_attack_timer.autostart = false  # Запускаем вручную через state machine
	add_child(auto_attack_timer)

func _start_auto_attack_delayed() -> void:
	"""
	Принудительно запускает автоатаку с задержкой для новых юнитов
	Вызывается через call_deferred после полной инициализации
	"""
	if is_multiplayer_authority() and auto_attack_timer:
		# Переводим юнит в состояние ожидания, что автоматически запустит таймер автоатаки
		unit_state = UNIT_STATES.IDLE

func _fix_visibility_after_init() -> void:
	"""
	ИСПРАВЛЕНИЕ ВИДИМОСТИ: Повторно настраивает видимость после полной инициализации
	Решает проблему когда боты видны противникам из-за неправильного порядка инициализации
	"""
	if not is_multiplayer_authority():
		return
	
	_last_visibility_update_frame = -100
	update_visibility()
	_rebuild_enemies_in_vision()

func _rebuild_enemies_in_vision() -> void:
	_enemies_in_vision.clear()
	var my_team = _get_cached_team()
	if my_team == null:
		return
	for unit in has_vision_on:
		if is_instance_valid(unit) and unit is BaseUnitServer and _is_enemy_unit_fast(unit, my_team):
			if unit not in _enemies_in_vision:
				_enemies_in_vision.append(unit)

func _on_auto_attack_timer_timeout() -> void:
	"""
	ОПТИМИЗИРОВАНО: Обработчик таймера автоматической атаки
	Теперь логика перенесена в _process_auto_attack_heavy() для FrameGroup системы
	"""
	# Оставляем пустой обработчик - логика перенесена в FrameGroup систему
	pass

func _get_visible_enemies() -> Array[BaseUnitServer]:
	"""Список врагов в зоне видимости (поддерживается сигналами Area2D)."""
	_profile_function_start("_get_visible_enemies")
	var i := _enemies_in_vision.size() - 1
	while i >= 0:
		if not is_instance_valid(_enemies_in_vision[i]):
			_enemies_in_vision.remove_at(i)
		i -= 1
	_profile_function_end("_get_visible_enemies")
	return _enemies_in_vision

func _is_enemy_unit_fast(unit: BaseUnitServer, my_team) -> bool:
	if not is_valid_unit(unit):
		return false
	if my_team != null and unit.owner_team != null:
		return my_team != unit.owner_team
	if owner_id != null and unit.owner_id != null:
		return owner_id != unit.owner_id
	return false

func _select_best_target(enemies: Array[BaseUnitServer]) -> BaseUnitServer:
	"""
	ОПТИМИЗИРОВАНО: Выбирает лучшую цель из списка врагов
	Добавлена проверка валидности и простая эвристика выбора
	"""
	if enemies.is_empty():
		return null
	
	# ОПТИМИЗАЦИЯ: Фильтруем валидные цели
	var valid_enemies: Array[BaseUnitServer] = []
	for enemy in enemies:
		if is_instance_valid(enemy):
			valid_enemies.append(enemy)
	
	if valid_enemies.is_empty():
		return null
	
	# УЛУЧШЕННЫЙ АЛГОРИТМ: Выбираем ближайшего врага
	var best_target: BaseUnitServer = valid_enemies[0]
	var best_distance = global_position.distance_squared_to(best_target.global_position)
	
	for i in range(1, valid_enemies.size()):
		var enemy = valid_enemies[i]
		var distance = global_position.distance_squared_to(enemy.global_position)
		if distance < best_distance:
			best_target = enemy
			best_distance = distance
	
	return best_target

func _get_bot_team_by_id(player_id: int) -> int:
	"""
	Получает команду бота по его ID
	Возвращает -1 если это не бот или бот не найден
	"""
	if not Handlers.GameHandler:
		return -1
	
	# Ищем бота в списке активных ботов
	for bot in Handlers.GameHandler.active_bots:
		if bot.bot_id == player_id:
			return int(bot.bot_team)
	
	return -1  # Не найден среди ботов

## СИСТЕМА ВОССТАНОВЛЕНИЯ ЩИТА
func _setup_shield_regeneration_timer() -> void:
	"""
	Создает и настраивает таймер восстановления щита
	Вызывается только на сервере при инициализации юнита
	"""
	shield_regeneration_timer = Timer.new()
	shield_regeneration_timer.wait_time = shield_regen_delay  # Начальная задержка
	shield_regeneration_timer.timeout.connect(_on_shield_regeneration_timeout)
	shield_regeneration_timer.autostart = false
	add_child(shield_regeneration_timer)

func _on_shield_regeneration_timeout() -> void:
	"""
	Обработчик таймера восстановления щита
	
	ЛОГИКА ВОССТАНОВЛЕНИЯ:
	1. Проверяет, что юнит в состоянии IDLE
	2. Восстанавливает щит постепенно (shield_regen_rate в секунду)
	3. Останавливается при достижении максимума
	"""
	# Восстановление работает только на сервере
	if not is_multiplayer_authority():
		return
	
	# Восстанавливаем щит только в состоянии ожидания
	if unit_state != UNIT_STATES.IDLE:
		return
	
	# Если щит уже полный - останавливаем таймер
	if _shield >= max_shield:
		shield_regeneration_timer.stop()
		return
	
	# Восстанавливаем щит
	var regen_amount = int(shield_regen_rate)  # Количество щита за тик
	shield += regen_amount
	
	# Если щит не полный - продолжаем восстановление каждую секунду
	if _shield < max_shield:
		shield_regeneration_timer.wait_time = 1.0  # Интервал восстановления
		shield_regeneration_timer.start()
	else:
		shield_regeneration_timer.stop()

## УЛУЧШЕННАЯ СИСТЕМА НАВИГАЦИИ
func _find_alternative_path_target(original_target: Vector2) -> Vector2:
	"""
	Ищет альтернативную цель когда прямой путь недоступен
	Использует алгоритм поиска доступных точек вокруг цели
	"""
	# Пробуем несколько точек вокруг оригинальной цели
	var test_distances = [50.0, 100.0, 150.0]  # Радиусы поиска
	var test_angles = [0, PI/4, PI/2, 3*PI/4, PI, 5*PI/4, 3*PI/2, 7*PI/4]  # 8 направлений
	
	for distance in test_distances:
		for angle in test_angles:
			var test_offset = Vector2(cos(angle), sin(angle)) * distance
			var test_position = original_target + test_offset
			
			# Проверяем доступность этой точки
			navagent.target_position = test_position
			if navagent.is_target_reachable():
				return test_position
	
	# Если ничего не найдено, используем ближайшую доступную точку
	navagent.target_position = original_target
	return navagent.get_final_position()

func _execute_smart_unstuck_maneuver(original_target: Vector2) -> void:
	"""
	Выполняет умный маневр для выхода из застревания
	Анализирует окружение и выбирает оптимальное направление
	"""
	var _is_bot = _get_bot_team_by_id(owner_id) != -1
	
	# Стратегия 1: Попытка обойти препятствие по дуге
	var direction_to_target = (original_target - global_position).normalized()
	var perpendicular_directions = [
		Vector2(-direction_to_target.y, direction_to_target.x),  # Левый перпендикуляр
		Vector2(direction_to_target.y, -direction_to_target.x)   # Правый перпендикуляр
	]
	
	# Пробуем обход по левой и правой стороне
	for perpendicular in perpendicular_directions:
		var detour_position = global_position + perpendicular * 80.0
		navagent.target_position = detour_position
		
		if navagent.is_target_reachable():
			return
	
	# Стратегия 2: Отступление назад для поиска нового пути
	var retreat_direction = -direction_to_target
	var retreat_position = global_position + retreat_direction * 60.0
	navagent.target_position = retreat_position
	
	if navagent.is_target_reachable():
		return
	
	# Стратегия 3: Случайное направление (последняя мера)
	var random_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var random_position = global_position + random_direction * 100.0
	navagent.target_position = random_position

# Переопределяем метод из базового класса
func get_target_position() -> Vector2:
	"""Возвращает целевую позицию юнита (для серверной логики)"""
	if navagent and navagent.is_target_reachable():
		return navagent.target_position
	else:
		return global_position

# Переопределяем визуальные методы из базового класса (заглушки для сервера)
func update_visual() -> void:
	"""Серверная версия - не обновляет визуал"""
	pass

func update_health_bar() -> void:
	"""Серверная версия - не обновляет UI"""
	pass

func update_shield_bar() -> void:
	"""Серверная версия - не обновляет UI"""
	pass
