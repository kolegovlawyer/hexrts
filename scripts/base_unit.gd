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
@export var health = 30
@export var damage = 5
@export var reload_time = 3

var preview

# Отладочные переменные для предотвращения спама в логах
var _last_attack_state: String = ""
var _attack_count: int = 0

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
	
	# Отладочная информация
	if is_multiplayer_authority():
		print("СЕРВЕРНЫЙ ЮНИТ СОЗДАН: ", name, " NodePath: ", get_path())
	else:
		print("КЛИЕНТСКИЙ ЮНИТ СОЗДАН: ", name, " NodePath: ", get_path())
	
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
		#owner_team = Handlers.TeamHandler.find_player_by_id(owner_id).Team
	
	update_visual()
	
func visibility_check_in(body):
	print('owner team in check ', owner_team)
	var team = Handlers.TeamHandler.get_team(owner_team)
	print(team)
	if body == self:
		return
	if body is BaseUnit:
		if not has_vision_on.has(body):
			print('ЗАМЕЧЕН ВРАГ')
			has_vision_on.append(body)
		if not body.visible_by.has(self):
			body.visible_by.append(self)
	
func visibility_check_out(body):
	pass
	
func on_velocity_computed(safe_velocity):
	velocity = safe_velocity
	
func preseclect():
	preselected = true
	
func depreselect():
	preselected = false
	
func handle_input(viewport, event, shape_idx):
	#print("handle_input ", event)
	print(name)
	if self in get_tree().get_nodes_in_group("own_units"):
		if event is InputEventMouseButton and event.button_index == 1:
			if event.pressed == false:
				print('we there')
				selected = true
				Handlers.UnitSelectionHandler.add_selected(self)
				get_viewport().set_input_as_handled()
	else:
		# Атака по правому клику на вражеском юните
		if event is InputEventMouseButton and event.button_index == 2:
			if event.pressed == false:
				print("АТАКА ЕПТА")
				print("selected_units: ", Handlers.UnitSelectionHandler.selected_units)
				for n in Handlers.UnitSelectionHandler.selected_units:
					print("Отправляем приказ атаки юниту: ", n.name)
					print("NodePath клиентского юнита: ", n.get_path())
					print("Имя цели (this.name): ", name)
					print("UID цели:", self.UID)
					# Передаем имя цели (this - это юнит, на который кликнули)
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
		
		# Обработка orders (должна быть ПЕРЕД проверкой navagent)
		if orders.size() > 0:
			#print("Обрабатываем orders. Размер: ", orders.size())
			var current_order = orders[0]
			#print("Текущий приказ: ", current_order)
			match current_order.type:
				"move":
					var pos = current_order.position
					navagent.target_position = pos
					if global_position.distance_to(pos) < 8.0:
						orders.pop_front()
						print("Приказ движения выполнен, удален")
				"attack":
					# Безопасная проверка цели перед присваиванием
					if not is_instance_valid(current_order.target):
						orders.pop_front()
						print("Цель недействительна, приказ удален")
					else:
						var target: BaseUnit = current_order.target
						attack(target)
		else:
			pass

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
	print("=== add_order ВЫЗВАНА ===")
	print("NodePath этого юнита: ", get_path())
	print("order_obj: ", order_obj, " типа: ", typeof(order_obj))
	print("owner_id: ", owner_id, " remote_sender: ", multiplayer.get_remote_sender_id())
	print("is_multiplayer_authority: ", is_multiplayer_authority())
	print("multiplayer.is_server(): ", multiplayer.is_server())
	print("multiplayer.get_unique_id(): ", multiplayer.get_unique_id())
	
	if owner_id != multiplayer.get_remote_sender_id(): # this must be in all units add_order
		print("Проверка owner_id не прошла")
		return
	if is_multiplayer_authority():
		print("Внутри is_multiplayer_authority")
		match typeof(order_obj):
			TYPE_VECTOR2:
				# Приказ на движение
				print('Получен приказ на движение')
				if clear_queue:
					orders.clear()
				orders.append({"type": "move", "position": order_obj})
				print("Добавлен приказ движения. Размер orders: ", orders.size())
			TYPE_STRING:
				# Приказ на атаку по имени
				print('Получен приказ на атаку по имени: ', order_obj)
				var target_unit = find_target_by_UID(order_obj)
				if target_unit is BaseUnit:
					if clear_queue:
						orders.clear()
					orders.append({"type": "attack", "target": target_unit})
					print("Добавлен приказ атаки. Размер orders: ", orders.size())
				else:
					print("Не удалось найти юнит по имени: ", order_obj)
	else:
		print("НЕ является multiplayer_authority")
		
@rpc("any_peer", "reliable")
func get_unit_info() -> void:
	#print("User ", multiplayer.get_remote_sender_id(), " requested unit info")
	rpc_id(multiplayer.get_remote_sender_id(), "set_unit_info", unit_profile.resource_path)	
	
func get_target_position():
	return(get_global_mouse_position())

func find_target_by_UID(target_uid: String) -> BaseUnit:
	# Ищем юнит по имени в дереве сцены
	var target = Handlers.GameHandler.units_dict[target_uid]
	if target:
		return target
	else:
		print('Цель не обнаружена по UID: ', target_uid)
		return null
	
func attack(target: BaseUnit) -> void:
	# Дополнительная проверка валидности цели
	if not is_instance_valid(target):
		print("❌ АТАКА: Цель стала невалидной во время атаки")
		return
		
	var current_state: String
	
	if reload_timer.time_left > 0:
		current_state = "cooldown"
		# Логируем только изменение состояния
		if _last_attack_state != current_state:
			print("🔄 АТАКА: Кулдаун активен (", reload_timer.time_left, "с)")
			_last_attack_state = current_state
		return
	
	current_state = "ready"
	if _last_attack_state != current_state:
		if _last_attack_state == "cooldown":
			print("✅ АТАКА: Кулдаун завершен, готов к атаке цели ", target.name)
		else:
			print("⚔️ АТАКА: Готов к атаке цели ", target.name)
		_last_attack_state = current_state
		_attack_count = 0
	
	emit_signal("attack_started", target)
	# Делегируем создание снаряда ProjectileSystem
	if Handlers.ProjectileHandler:
		Handlers.ProjectileHandler.rpc("create_projectile", UID, target.UID, damage)
		print("🚀 АТАКА: Запрос снаряда отправлен в ProjectileSystem")
	else:
		print("❌ АТАКА: ProjectileSystem не найден")
	
	reload_timer.wait_time = reload_time  # Убеждаемся, что используется правильное время
	reload_timer.start()
	print("⏰ АТАКА: Кулдаун запущен на ", reload_timer.wait_time, " секунд")
	
	_last_attack_state = "fired"

func apply_damage(amount: int, from: BaseUnit) -> void:
	health -= amount
	print("Unit ", name, " took ", amount, " damage from ", from.name, ". Health: ", health)
	if health <= 0:
		die()

func die() -> void:
	print("💀 Unit died: ", name)
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
	
func update_visual():
	print("update_visual", owner_id, Handlers.TeamHandler.my_profile)
	if not Handlers.TeamHandler.my_profile:
		return
	if owner_id == 1:
		if not is_multiplayer_authority():
			print("А ВОТ И Я!!!")
		return
		
	var player = Handlers.TeamHandler.find_player_by_id(owner_id)
	if not player:  # Добавляем проверку
		print("Player not found for owner_id: ", owner_id)
		return
		
	owner_team = player.Team
	if owner_id == Handlers.TeamHandler.my_profile.PlayerId:
		add_to_group("own_units")
		if not preview:
			var self_preview = preload("res://prefabs/ui/unit_preview.tscn").instantiate()
			preview = self_preview
		#preview.update_visual()
		Handlers.UIHandler.unit_container.add_child(preview)
		preview.unit = self
		return
	elif Handlers.TeamHandler.find_player_by_id(owner_id).Team == Handlers.TeamHandler.my_profile.Team:
		sprite.self_modulate = Color(0, 0, 1)
		print('ALLY')
	else:
		if sprite:
			sprite.self_modulate = Color(1, 0, 0)
			light.hide()
			sprite.light_mask = 2
			sprite.visibility_layer = 2
			print('check')
		
func update_visibility():
	if is_multiplayer_authority():
		for player in Handlers.TeamHandler.get_team_players(Handlers.TeamHandler.find_player_by_id(owner_id).Team):
			synchronizer.set_visibility_for(player.PlayerId, true)
			
func set_visibility_for_enemy(is_visible:bool) -> void:
	if is_multiplayer_authority():
		for player in Handlers.TeamHandler.get_enemy_team_players(Handlers.TeamHandler.find_player_by_id(owner_id).Team):
			synchronizer.set_visibility_for(player.PlayerId, is_visible)
