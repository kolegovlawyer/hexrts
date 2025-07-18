class_name BaseUnit extends CharacterBody2D

### SERVER AND UNIT CODE

const SPEED = 300.0

@onready var collision = get_node("%CollisionShape2D")
@onready var selection_ring = get_node("%UnitSelectionRing")
@onready var sprite = get_node("%UnitSelfSprite")
@onready var arrow = get_node("%ArrowSprite")
@onready var light = get_node("%Light")
@onready var synchronizer = get_node("%MultiplayerSynchronizer")
@onready var visibility_area = get_node("%VisibilityArea")
@onready var reload_timer = get_node("%ReloadTimer")
@onready var aim_taimer = get_node("%AimTimer")
@onready var health_bar = get_node("%HealthBar")
@onready var shield_bar = get_node("%ShiledBar")

# Таймер для автоматической атаки (проверка каждую секунду)
var auto_attack_timer: Timer

# Таймер для восстановления щита
var shield_regeneration_timer: Timer

@onready var navagent : NavigationAgent2D = $NavigationAgent2D
var path_points : Array[Vector2] = []

@onready var UID = ''

var unit_profile = ''
@export var owner_id : int = 1:
	set(value):
		if value == 1:
			print('WHO I AM???')
			return
		else:
			owner_id = value
		if not is_multiplayer_authority():
			#update_visual()
			pass
		else:
			synchronizer.owner_id = value
			owner_team = Handlers.TeamHandler.find_player_by_id(owner_id).Team
			update_visibility()
			
var owner_team

#@export var health : float

var visible_by : Array[BaseUnit] = []
var has_vision_on : Array[BaseUnit] = []

var orders = []
var current_order

## СИСТЕМА СОСТОЯНИЙ ЮНИТА (STATE MACHINE)
# Определяет текущее поведение и логику принятия решений
enum UNIT_STATES {
	IDLE,           # Бездействие - ожидает приказов или ищет цели
	MOVING,         # Движется к заданной позиции
	ATTACKING,      # Атакует конкретную цель
	AUTO_ATTACKING  # Автоматически атакует ближайшего врага
}

var unit_state: int = UNIT_STATES.IDLE:
	set(value):
		if value == unit_state:
			return
			
		# Отладочная информация о смене состояния
		# print("🤖 ", name, " состояние: ", UNIT_STATES.keys()[unit_state], " → ", UNIT_STATES.keys()[value])  # DEBUG
		
		# Выход из предыдущего состояния
		_unit_state_exit(unit_state)
		unit_state = value
		# Вход в новое состояние
		_unit_state_enter(unit_state)


var preselected : bool = false:
	set(value):
		preselected = value
		if value == true:
			selection_ring.show()
		else:
			selection_ring.hide()
			
var selected : bool = false:
	set(value):
		### DEBUG
		print('Unit selected is ', value)
		
		selected = value
		if value == true:
			$UnitSelfSprite.self_modulate = Color(0.37, 0.37, 0.37)#(255, 50, 255, 255)
		if value == false:
			$UnitSelfSprite.self_modulate = Color(1, 1, 1)
			
### Характеристики, которые должны заполняться из unit_profile
			
var accel = 7
@export var speed = 300
@export var max_health = 30
@export var max_shield = 15  # По умолчанию 1/2 от здоровья
@export var damage = 5
@export var reload_time = 3
@export var shield_regen_rate = 1.5  # Щит в секунду при восстановлении (15/10 = 1.5)
@export var shield_regen_delay = 3.0  # Задержка начала восстановления щита после получения урона

var _health = 30
var _shield = 15

@export var health: int:
	set(value):
		var old_health = _health
		_health = clamp(value, 0, max_health)
		if old_health != _health:
			update_health_bar()
			# print("🩹 Health изменен с ", old_health, " на ", _health)
	get:
		return _health

@export var shield: int:
	set(value):
		var old_shield = _shield
		_shield = clamp(value, 0, max_shield)
		if old_shield != _shield:
			update_shield_bar()
			# Отправляем обновление щита клиентам (только с сервера)
			if is_multiplayer_authority():
				rpc("sync_shield", _shield)
			# print("🛡️ Shield изменен с ", old_shield, " на ", _shield)
	get:
		return _shield

var preview

# Отладочные переменные для предотвращения спама в логах
var _last_attack_state: String = ""
var _attack_count: int = 0

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
	
	# Добавляем в группу units для поиска
	add_to_group("units")
	
	# Инициализируем health bar и shield bar
	init_health_bar()
	init_shield_bar()
	
	# Создаем таймер автоматической атаки (только на сервере)
	if is_multiplayer_authority():
		_setup_auto_attack_timer()
		_setup_shield_regeneration_timer()
	
	
	if not is_multiplayer_authority():
		connect("input_event", handle_input)
		connect("mouse_entered", preseclect)
		connect("mouse_exited", depreselect)
		navagent.queue_free()
		update_visual()
	else:
		UID = str(generate_numeric_id(10))
		$DebugLabel.text = "СЕРВЕРНЫЙ ЧЕЛИКС"
		Handlers.GameHandler.units_dict[UID] = self
		navagent.connect("velocity_computed", on_velocity_computed)
		visibility_area.connect("body_entered", visibility_check_in)
		visibility_area.connect("body_exited", visibility_check_out)
		print('ОВНЕР АЙДИ ПЕРЕД ТЕМ КАК СЛОМАТЬСЯ ', owner_id)
		print(Handlers.TeamHandler.find_player_by_id(owner_id))
		# КРИТИЧЕСКИ ВАЖНО: Инициализируем owner_team для новых юнитов
		if owner_id != 1:  # Не для дефолтного значения
			var player = Handlers.TeamHandler.find_player_by_id(owner_id)
			if player:
				owner_team = player.Team
				print("🏷️ ИНИЦИАЛИЗАЦИЯ: owner_team установлен в ", owner_team, " для юнита ", name)
				
				# Запускаем автоатаку с небольшой задержкой для полной инициализации
				call_deferred("_start_auto_attack_delayed")
			else:
				print("⚠️ ОШИБКА: Игрок с owner_id ", owner_id, " не найден при инициализации юнита")
	
	update_visual()
	last_move_position = global_position
	
func visibility_check_in(body):
	# print('owner team in check ', owner_team)
	var team = Handlers.TeamHandler.get_team(owner_team)
	# print(team)
	if body == self:
		return
	if body is BaseUnit:
		if not has_vision_on.has(body):
			# print('ЗАМЕЧЕН ВРАГ')
			has_vision_on.append(body)
		if not body.visible_by.has(self):
			body.visible_by.append(self)
	
func visibility_check_out(body):
	if body == self:
		return
	if body is BaseUnit:
		if has_vision_on.has(body):
			# print('ВРАГ ВЫШЕЛ ИЗ ПОЛЯ ЗРЕНИЯ: ', body.name)
			has_vision_on.erase(body)
		if body.visible_by.has(self):
			body.visible_by.erase(self)
	
func on_velocity_computed(safe_velocity):
	velocity = safe_velocity
	
func preseclect():
	preselected = true
	
func depreselect():
	preselected = false
	
func handle_input(viewport, event, shape_idx):
	#print("handle_input ", event)
	# print(name)
	if self in get_tree().get_nodes_in_group("own_units"):
		if event is InputEventMouseButton and event.button_index == 1:
			if event.pressed == false:
				# print('we there')
				selected = true
				Handlers.UnitSelectionHandler.add_selected(self)
				get_viewport().set_input_as_handled()
	else:
		# Атака по правому клику на вражеском юните
		if event is InputEventMouseButton and event.button_index == 2:
			if event.pressed == false:
				# print("АТАКА ЕПТА")
				# print("selected_units: ", Handlers.UnitSelectionHandler.selected_units)
				for n in Handlers.UnitSelectionHandler.selected_units:
					# print("Отправляем приказ атаки юниту: ", n.name)
					# print("NodePath клиентского юнита: ", n.get_path())
					# print("Имя цели (this.name): ", name)
					# print("UID цели:", self.UID)
					# Передаем имя цели (this - это юнит, на который кликнули)
					if is_instance_valid(n):
						n.rpc_id(1, "add_order", UID, true)
				get_viewport().set_input_as_handled()
		# Блокируем UI обработку при любом клике на юните
		elif event is InputEventMouseButton:
			get_viewport().set_input_as_handled()



func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		
		if visible_by:
			set_visibility_for_enemy(true)
		else:
			set_visibility_for_enemy(false)
		
		# Обработка orders с учетом state machine
		if orders.size() > 0:
			var current_order = orders[0]
			match current_order.type:
				"move":
					# Переключаемся в состояние движения
					if unit_state != UNIT_STATES.MOVING:
						unit_state = UNIT_STATES.MOVING
					
					var pos = current_order.position
					navagent.target_position = pos
					
					# Новый: увеличенный порог и проверка навигатора
					var close_enough = global_position.distance_to(pos) < 16.0
					var nav_done = navagent.is_navigation_finished()
					var moved = global_position.distance_to(last_move_position) > 1.0
					
					if close_enough or nav_done:
						orders.pop_front()
						# print("✅ ДВИЖЕНИЕ: Приказ движения выполнен для юнита ", name)
						unit_state = UNIT_STATES.IDLE
						stuck_timer = 0.0
					elif not moved:
						stuck_timer += delta
						if stuck_timer > 2.0:
							# print("⚠️ ДВИЖЕНИЕ: Юнит застрял, удаляем приказ")
							orders.pop_front()
							unit_state = UNIT_STATES.IDLE
							stuck_timer = 0.0
					else:
						stuck_timer = 0.0
					last_move_position = global_position
					
				"attack":
					# Переключаемся в состояние атаки
					if unit_state != UNIT_STATES.ATTACKING and unit_state != UNIT_STATES.AUTO_ATTACKING:
						unit_state = UNIT_STATES.ATTACKING
					
					# Безопасная проверка цели
					if not is_instance_valid(current_order.target):
						orders.pop_front()
						# print("Цель недействительна, приказ удален")  # DEBUG
						unit_state = UNIT_STATES.IDLE
					else:
						var target: BaseUnit = current_order.target
						# Проверяем видимость цели
						if not can_see_target(target):
							orders.pop_front()
							# print("👁️ Цель ", target.name, " не видна, приказ отменен")  # DEBUG
							unit_state = UNIT_STATES.IDLE
						else:
							attack(target)
		else:
			# Нет приказов - переходим в состояние ожидания для автоатаки
			if unit_state != UNIT_STATES.IDLE and unit_state != UNIT_STATES.AUTO_ATTACKING:
				unit_state = UNIT_STATES.IDLE

		# Движение (только если navagent не завершен)
		if not navagent.is_navigation_finished():
			var current_unit_position = global_position
			var next_path_position = navagent.get_next_path_position()
			#arrow.look_at(to_global(navagent.target_position)) # TODO : пофиксить вращение стрелки к цели
			# arrow.rotate(arrow.get_angle_to(navagent.target_position))
			velocity = current_unit_position.direction_to(next_path_position)*speed
			move_and_slide()
			$DebugLabel.text = str(global_position)
			$DebugLabel2.text = str(position)
		
		### проверка целей для атаки
				
@rpc("any_peer", "reliable")
func add_order(order_obj, clear_queue:bool=false) -> void:
	# print("=== add_order ВЫЗВАНА ===")
	# print("NodePath этого юнита: ", get_path())
	# print("order_obj: ", order_obj, " типа: ", typeof(order_obj))
	# print("owner_id: ", owner_id, " remote_sender: ", multiplayer.get_remote_sender_id())
	# print("is_multiplayer_authority: ", is_multiplayer_authority())
	# print("multiplayer.is_server(): ", multiplayer.is_server())
	# print("multiplayer.get_unique_id(): ", multiplayer.get_unique_id())
	
	if owner_id != multiplayer.get_remote_sender_id(): # this must be in all units add_order
		# print("Проверка owner_id не прошла")
		return
	if is_multiplayer_authority():
		# print("Внутри is_multiplayer_authority")
		match typeof(order_obj):
			TYPE_VECTOR2:
				# Приказ на движение
				# print('Получен приказ на движение')
				if clear_queue:
					orders.clear()
				orders.append({"type": "move", "position": order_obj})
				# print("Добавлен приказ движения. Размер orders: ", orders.size())
			TYPE_STRING:
				# Приказ на атаку по имени
				# print('Получен приказ на атаку по имени: ', order_obj)
				var target_unit = find_target_by_UID(order_obj)
				if target_unit is BaseUnit:
					# Проверяем видимость цели перед добавлением приказа
					if can_see_target(target_unit):
						if clear_queue:
							orders.clear()
						orders.append({"type": "attack", "target": target_unit})
						# print("Добавлен приказ атаки. Размер orders: ", orders.size())
					else:
						# print("👁️ ADD_ORDER: Цель ", target_unit.name, " не видна, приказ атаки отклонен")
						pass
				else:
					# print("Не удалось найти юнит по имени: ", order_obj)
					pass
	else:
		# print("НЕ является multiplayer_authority")
		pass
		
@rpc("any_peer", "reliable")
func get_unit_info() -> void:
	#print("User ", multiplayer.get_remote_sender_id(), " requested unit info")
	rpc_id(multiplayer.get_remote_sender_id(), "set_unit_info", unit_profile.resource_path)	

@rpc("any_peer", "reliable")
func clear_orders() -> void:
	"""
	Очищает все приказы юнита и переводит его в состояние ожидания
	Вызывается при снятии выделения с юнита
	"""
	if owner_id != multiplayer.get_remote_sender_id():
		# print("Проверка owner_id для clear_orders не прошла")
		return
		
	if is_multiplayer_authority():
		# print("🗑️ CLEAR_ORDERS: Очистка приказов для юнита ", name)
		orders.clear()
		# Переводим юнит в состояние ожидания для автоатаки
		unit_state = UNIT_STATES.IDLE
		# print("✅ CLEAR_ORDERS: Юнит ", name, " переведен в состояние IDLE для автоатаки")
	
func get_target_position():
	return(get_global_mouse_position())

func find_target_by_UID(target_uid: String) -> BaseUnit:
	# Ищем юнит по имени в дереве сцены
	var target = Handlers.GameHandler.units_dict[target_uid]
	if target:
		return target
	else:
		# print('Цель не обнаружена по UID: ', target_uid)
		return null

func can_see_target(target: BaseUnit) -> bool:
	"""Проверяет, может ли юнит видеть указанную цель"""
	if not is_instance_valid(target):
		return false
	return has_vision_on.has(target)
	
func attack(target: BaseUnit) -> void:
	# Дополнительная проверка валидности цели
	if not is_instance_valid(target):
		# print("❌ АТАКА: Цель стала невалидной во время атаки")
		return
	
	# Проверка видимости цели
	if not can_see_target(target):
		# print("👁️ АТАКА: Цель ", target.name, " не видна, атака прекращена")
		# Удаляем приказ атаки, так как цель невидима
		if orders.size() > 0 and orders[0].type == "attack":
			orders.pop_front()
			# print("🚫 АТАКА: Приказ атаки удален из-за потери видимости")
		return
		
	var current_state: String
	
	if reload_timer.time_left > 0:
		current_state = "cooldown"
		# Логируем только изменение состояния
		if _last_attack_state != current_state:
			# print("🔄 АТАКА: Кулдаун активен (", reload_timer.time_left, "с)")
			_last_attack_state = current_state
		return
	
	current_state = "ready"
	if _last_attack_state != current_state:
		if _last_attack_state == "cooldown":
			# print("✅ АТАКА: Кулдаун завершен, готов к атаке цели ", target.name)
			pass
		else:
			# print("⚔️ АТАКА: Готов к атаке цели ", target.name)
			pass
		_last_attack_state = current_state
		_attack_count = 0
	
	emit_signal("attack_started", target)
	# Делегируем создание снаряда централизованной системе ProjectileSystem
	# Это обеспечивает правильное разделение серверной логики и клиентской визуализации
	if Handlers.ProjectileHandler:
		var explosion_radius = 50.0  # Радиус взрыва (можно сделать настраиваемым параметром юнита)
		Handlers.ProjectileHandler.rpc("create_projectile", UID, target.UID, damage, explosion_radius)
		# print("🚀 АТАКА: Запрос снаряда отправлен в ProjectileSystem")  # DEBUG
	else:
		# print("❌ АТАКА: ProjectileSystem не найден")  # DEBUG
		pass
	
	reload_timer.wait_time = reload_time  # Убеждаемся, что используется правильное время
	reload_timer.start()
	# print("⏰ АТАКА: Кулдаун запущен на ", reload_timer.wait_time, " секунд")
	
	_last_attack_state = "fired"

func apply_damage(amount: int, from: BaseUnit = null) -> void:
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
	var remaining_damage = amount
	
	# Сначала урон поглощается щитом
	if _shield > 0:
		var shield_damage = min(_shield, remaining_damage)
		shield -= shield_damage
		remaining_damage -= shield_damage
		
		# Останавливаем восстановление щита и сбрасываем таймер
		if is_multiplayer_authority() and shield_regeneration_timer:
			shield_regeneration_timer.stop()
			# Перезапускаем таймер задержки восстановления
			shield_regeneration_timer.wait_time = shield_regen_delay
			shield_regeneration_timer.start()
		
		# print("🛡️ Щит поглотил ", shield_damage, " урона. Щит: ", _shield, "/", max_shield)
	
	# Оставшийся урон наносится здоровью
	if remaining_damage > 0:
		health -= remaining_damage
	
	# Безопасное логирование с проверкой источника урона
	if from and is_instance_valid(from):
		# print("Unit ", name, " took ", amount, " damage from ", from.name, ". Shield: ", _shield, " Health: ", _health)
		pass
	else:
		# print("Unit ", name, " took ", amount, " damage from unknown source. Shield: ", _shield, " Health: ", _health)
		pass
	
	if health <= 0:
		die()

@rpc("any_peer", "call_local", "reliable")
func sync_shield(new_shield_value: int) -> void:
	"""
	Синхронизирует значение щита между сервером и клиентами
	Вызывается только с сервера при изменении щита
	"""
	if not is_multiplayer_authority():
		_shield = new_shield_value
		update_shield_bar()

func die() -> void:
	# print(" Unit died: ", name)
	
	# Удаляем юнит из выделения (только для владельца)
	if not is_multiplayer_authority() and self in get_tree().get_nodes_in_group("own_units"):
		if Handlers.UnitSelectionHandler:
			Handlers.UnitSelectionHandler.remove_unit_from_selection(self)
	
	# Очищаем все ссылки на этот юнит
	visible_by.clear()
	has_vision_on.clear()
	# Уведомляем всех, кто мог на нас ссылаться
	get_tree().call_group("units", "_on_unit_died", self)
	queue_free()

func _on_unit_died(dead_unit: BaseUnit) -> void:
	# Удаляем умершего юнита из наших списков
	if dead_unit in visible_by:
		visible_by.erase(dead_unit)
	if dead_unit in has_vision_on:
		has_vision_on.erase(dead_unit)

## HEALTH BAR FUNCTIONS ##

func init_health_bar() -> void:
	"""Инициализирует health bar с правильными значениями"""
	# Инициализируем здоровье и щит, если еще не инициализированы
	if _health <= 0:
		_health = max_health
	if _shield <= 0:
		_shield = max_shield
	
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = _health
		update_health_bar()  # Обновляем отображение с правильными цветами
		# print("🏥 Health bar инициализирован: ", _health, "/", max_health)

func update_health_bar() -> void:
	"""Обновляет отображение health bar при изменении здоровья"""
	if health_bar:
		health_bar.value = _health
		
		# Меняем цвет в зависимости от процента здоровья
		var health_percent = float(_health) / float(max_health)
		if health_percent > 0.7:
			# Зеленый цвет для здорового состояния
			health_bar.modulate = Color.GREEN
		elif health_percent > 0.3:
			# Желтый цвет для поврежденного состояния
			health_bar.modulate = Color.YELLOW
		else:
			# Красный цвет для критического состояния
			health_bar.modulate = Color.RED
		
		# print("💚 Health bar обновлен: ", _health, "/", max_health, " (", int(health_percent * 100), "%)")
	
func update_visual():
	# print("update_visual", owner_id, Handlers.TeamHandler.my_profile)
	if not Handlers.TeamHandler.my_profile:
		return
	if owner_id == 1:
		if not is_multiplayer_authority():
			# print("А ВОТ И Я!!!")
			pass
		return
		
	var player = Handlers.TeamHandler.find_player_by_id(owner_id)
	if not player:
		# print("Player not found for owner_id: ", owner_id)
		return
		
	owner_team = player.Team
	if owner_id == Handlers.TeamHandler.my_profile.PlayerId:
		set_own_unit_group()
		if not preview:
			var self_preview = preload("res://prefabs/ui/unit_preview.tscn").instantiate()
			preview = self_preview
		Handlers.UIHandler.unit_container.add_child(preview)
		preview.unit = self
		return
	elif Handlers.TeamHandler.find_player_by_id(owner_id).Team == Handlers.TeamHandler.my_profile.Team:
		update_sprite_color()
		# print('ALLY')
	else:
		update_sprite_color()
		# print('check')
	update_health_bar()
	update_shield_bar()

# === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ РЕФАКТОРИНГА ===
func is_valid_unit(unit) -> bool:
	"""Проверяет, что объект существует и является BaseUnit"""
	return unit != null and is_instance_valid(unit) and unit is BaseUnit

func set_own_unit_group():
	if not is_in_group("own_units"):
		add_to_group("own_units")

func set_enemy_unit_group():
	if not is_in_group("enemy_units"):
		add_to_group("enemy_units")

func update_sprite_color():
	if owner_id == Handlers.TeamHandler.my_profile.PlayerId:
		sprite.self_modulate = Color(1, 1, 1)
	elif owner_team == Handlers.TeamHandler.my_profile.Team:
		sprite.self_modulate = Color(0, 0, 1)
	else:
		sprite.self_modulate = Color(1, 0, 0)
		if light:
			light.hide()
		if sprite:
			sprite.light_mask = 2
			sprite.visibility_layer = 2
		
func update_visibility():
	if is_multiplayer_authority():
		for player in Handlers.TeamHandler.get_team_players(Handlers.TeamHandler.find_player_by_id(owner_id).Team):
			synchronizer.set_visibility_for(player.PlayerId, true)
			
func set_visibility_for_enemy(is_visible:bool) -> void:
	if is_multiplayer_authority():
		for player in Handlers.TeamHandler.get_enemy_team_players(Handlers.TeamHandler.find_player_by_id(owner_id).Team):
			synchronizer.set_visibility_for(player.PlayerId, is_visible)

## СИСТЕМА СОСТОЯНИЙ (STATE MACHINE)
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
			# В состоянии ожидания запускаем поиск целей для автоатаки
			if auto_attack_timer and is_multiplayer_authority():
				auto_attack_timer.start()
				# print("🎯 AUTO_ATTACK: Таймер запущен для юнита ", name, " (переход в IDLE)")
			# В состоянии ожидания начинаем восстановление щита (если щит не полный)
			if shield_regeneration_timer and is_multiplayer_authority() and _shield < max_shield:
				shield_regeneration_timer.wait_time = shield_regen_delay
				shield_regeneration_timer.start()
				# print("🛡️ SHIELD_REGEN: Таймер задержки восстановления запущен для ", name)
		UNIT_STATES.MOVING:
			# В состоянии движения останавливаем поиск целей и восстановление щита
			if auto_attack_timer:
				auto_attack_timer.stop()
			if shield_regeneration_timer and is_multiplayer_authority():
				shield_regeneration_timer.stop()
				# print("🛡️ SHIELD_REGEN: Восстановление остановлено (движение)")
		UNIT_STATES.ATTACKING:
			# В состоянии атаки останавливаем поиск целей и восстановление щита
			if auto_attack_timer:
				auto_attack_timer.stop()
			if shield_regeneration_timer and is_multiplayer_authority():
				shield_regeneration_timer.stop()
				# print("🛡️ SHIELD_REGEN: Восстановление остановлено (атака)")
		UNIT_STATES.AUTO_ATTACKING:
			# В состоянии автоатаки таймер поиска работает, но восстановление щита останавливается
			if auto_attack_timer and is_multiplayer_authority():
				auto_attack_timer.start()
			if shield_regeneration_timer and is_multiplayer_authority():
				shield_regeneration_timer.stop()
				# print("🛡️ SHIELD_REGEN: Восстановление остановлено (автоатака)")

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
	
	# print("🎯 Таймер автоатаки настроен для ", name)  # DEBUG

func _start_auto_attack_delayed() -> void:
	"""
	Принудительно запускает автоатаку с задержкой для новых юнитов
	Вызывается через call_deferred после полной инициализации
	"""
	if is_multiplayer_authority() and auto_attack_timer:
		# Переводим юнит в состояние ожидания, что автоматически запустит таймер автоатаки
		unit_state = UNIT_STATES.IDLE
		# print("🎯 AUTO_ATTACK: Принудительно запущена автоатака для нового юнита ", name)

func _on_auto_attack_timer_timeout() -> void:
	"""
	Обработчик таймера автоматической атаки
	Вызывается каждую секунду для поиска и атаки врагов
	
	ЛОГИКА АВТОАТАКИ:
	1. Проверяет, нет ли текущих приказов (приоритет у ручных команд)
	2. Ищет видимых врагов в зоне обзора
	3. Выбирает ближайшего врага как цель
	4. Добавляет приказ атаки в очередь
	5. Переключает состояние на AUTO_ATTACKING
	"""
	# Автоатака работает только на сервере
	if not is_multiplayer_authority():
		return
	# print("🔄 AUTO_ATTACK: Таймер сработал для юнита ", name, " (orders: ", orders.size(), ")")
	# Не атакуем автоматически если есть активные приказы (приоритет у игрока)
	if orders.size() > 0:
		# print("🤖 AUTO_ATTACK: ", name, " - есть приказы, автоатака отложена")
		return
	# Ищем видимых врагов
	var visible_enemies = _get_visible_enemies()
	# print("👁️ AUTO_ATTACK: ", name, " видит врагов: ", visible_enemies.size())
	if visible_enemies.is_empty():
		# Нет врагов - переходим в состояние ожидания
		if unit_state != UNIT_STATES.IDLE:
			unit_state = UNIT_STATES.IDLE
		# print("😴 AUTO_ATTACK: ", name, " - нет врагов, остаемся в ожидании")
		return
	# Выбираем ближайшего врага (первый в списке)
	var target_enemy = _select_best_target(visible_enemies)
	if is_valid_unit(target_enemy):
		# print("🎯 AUTO_ATTACK: ", name, " выбрал цель для автоатаки: ", target_enemy.name)
		orders.append({"type": "attack", "target": target_enemy})
		unit_state = UNIT_STATES.AUTO_ATTACKING

# === END ВСПОМОГАТЕЛЬНЫХ ===

func _get_visible_enemies() -> Array[BaseUnit]:
	"""
	Возвращает список всех видимых вражеских юнитов
	Использует систему видимости has_vision_on и проверяет принадлежность к команде
	"""
	var enemies: Array[BaseUnit] = []
	
	for unit in has_vision_on:
		if is_instance_valid(unit) and unit != self:
			# КРИТИЧЕСКИ ВАЖНО: Проверяем, что это действительно враг, а не союзник
			if _is_enemy_unit(unit):
				enemies.append(unit)
			# else:
				# print("🤝 АВТОАТАКА: Игнорируем союзника ", unit.name)  # DEBUG
	
	return enemies

func _is_enemy_unit(unit: BaseUnit) -> bool:
	"""
	Определяет, является ли юнит вражеским по отношению к этому юниту
	
	АЛГОРИТМ ОПРЕДЕЛЕНИЯ:
	1. Проверяет команды через owner_team
	2. Если команды не определены, сравнивает owner_id 
	3. При неопределенности возвращает false (не атакуем)
	
	ВОЗВРАЩАЕТ:
	- true: Юнит является врагом (можно атаковать)
	- false: Юнит является союзником или неопределен (атаковать нельзя)
	"""
	# Проверяем валидность объектов
	if not is_valid_unit(unit):
		return false  # Невалидные юниты не атакуем
	
	# СПОСОБ 1: Сравнение команд через owner_team (основной)
	if owner_team != null and unit.owner_team != null:
		var is_enemy = owner_team != unit.owner_team
		# print("🔍 КОМАНДЫ: Моя команда (", owner_team, ") vs команда цели (", unit.owner_team, ") = враг: ", is_enemy)  # DEBUG
		return is_enemy
	
	# СПОСОБ 2: Сравнение через owner_id (резервный)
	if owner_id != null and unit.owner_id != null:
		var is_enemy = owner_id != unit.owner_id
		# print("🔍 OWNER_ID: Мой owner_id (", owner_id, ") vs owner_id цели (", unit.owner_id, ") = враг: ", is_enemy)  # DEBUG
		return is_enemy
	
	# СПОСОБ 3: По умолчанию НЕ считаем вражеским (осторожная стратегия)
	# Лучше не атаковать неопределенную цель, чем атаковать союзника
	# print("🔍 АВТОАТАКА: Не удалось определить принадлежность для ", unit.name, ", НЕ атакуем")  # DEBUG
	return false

func _select_best_target(enemies: Array[BaseUnit]) -> BaseUnit:
	"""
	Выбирает лучшую цель из списка врагов
	
	АЛГОРИТМ ВЫБОРА:
	1. Берет первого врага из списка (простейший алгоритм)
	2. В будущем можно усложнить: ближайший, самый слабый, наиболее опасный
	
	ПАРАМЕТРЫ:
	- enemies: Список доступных для атаки врагов
	
	ВОЗВРАЩАЕТ:
	- BaseUnit: Выбранная цель или null если список пуст
	"""
	if enemies.is_empty():
		return null
	
	# Простейший алгоритм - берем первого
	# TODO: Можно улучшить логику выбора цели:
	# - Ближайший враг
	# - Самый слабый (меньше здоровья)
	# - Наиболее опасный (больше урона)
	# - Приоритет по типу юнита
	
	return enemies[0]

## SHIELD BAR FUNCTIONS ##

func init_shield_bar() -> void:
	"""Инициализирует shield bar с правильными значениями"""
	# Инициализируем щит, если еще не инициализирован
	if _shield <= 0:
		_shield = max_shield
	
	if shield_bar:
		shield_bar.max_value = max_shield
		shield_bar.value = _shield
		update_shield_bar()  # Обновляем отображение с правильными цветами
		# print("🛡️ Shield bar инициализирован: ", _shield, "/", max_shield)

func update_shield_bar() -> void:
	"""Обновляет отображение shield bar при изменении щита"""
	if shield_bar:
		shield_bar.value = _shield
		
		# Меняем цвет в зависимости от процента щита
		var shield_percent = float(_shield) / float(max_shield)
		if shield_percent > 0.7:
			# Синий цвет для полного щита
			shield_bar.modulate = Color.CYAN
		elif shield_percent > 0.3:
			# Фиолетовый цвет для поврежденного щита
			shield_bar.modulate = Color.MAGENTA
		elif shield_percent > 0:
			# Красный цвет для критического щита
			shield_bar.modulate = Color.ORANGE
		else:
			# Скрываем bar когда щита нет
			shield_bar.modulate = Color.TRANSPARENT
		
		# print("🛡️ Shield bar обновлен: ", _shield, "/", max_shield, " (", int(shield_percent * 100), "%)")

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
	
	# print("🛡️ Таймер восстановления щита настроен для ", name)

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
		# print("🛡️ SHIELD_REGEN: Щит полностью восстановлен для ", name)
		return
	
	# Восстанавливаем щит
	var regen_amount = int(shield_regen_rate)  # Количество щита за тик
	shield += regen_amount
	
	# print("🛡️ SHIELD_REGEN: Восстановлено ", regen_amount, " щита для ", name, " (", _shield, "/", max_shield, ")")
	
	# Если щит не полный - продолжаем восстановление каждую секунду
	if _shield < max_shield:
		shield_regeneration_timer.wait_time = 1.0  # Интервал восстановления
		shield_regeneration_timer.start()
	else:
		shield_regeneration_timer.stop()
