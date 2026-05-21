class_name Hex extends RefCounted

# Статус захвата гекса
# -1 = нейтральный/не захваченный
# 0 = команда A, 1 = команда B, 2 = команда C, и т.д.
@export var team_owner: int = -1

# Список командных юнитов, находящихся на гексе
var command_units: Array[BaseUnit] = []

# Позиция гекса на карте (координаты тайла)
var position: Vector2i

# Прогресс захвата (от 0.0 до 1.0)
var capture_progress: float = 0.0

# Команда, которая сейчас пытается захватить гекс
# -1 = никто не захватывает, 0+ = номер команды
var capturing_team: int = -1

func _init(hex_position: Vector2i, initial_team: int = -1):
	position = hex_position
	team_owner = initial_team

func add_command_unit(unit: BaseUnit) -> void:
	"""Добавляет командный юнит на гекс"""
	if unit not in command_units:
		command_units.append(unit)
		print("🎖️ ГЕКС: Командный юнит ", unit.name, " добавлен на гекс ", position)

func remove_command_unit(unit: BaseUnit) -> void:
	"""Удаляет командный юнит с гекса"""
	if unit in command_units:
		command_units.erase(unit)
		print("🎖️ ГЕКС: Командный юнит ", unit.name, " покинул гекс ", position)

func get_command_units_by_team(team: int) -> Array[BaseUnit]:
	"""Возвращает список командных юнитов определенной команды на гексе"""
	var team_units: Array[BaseUnit] = []
	for unit in command_units:
		if is_instance_valid(unit) and unit.owner_team == team:
			team_units.append(unit)
	return team_units

func has_enemy_command_units(friendly_team: int) -> bool:
	"""Проверяет, есть ли на гексе вражеские командные юниты"""
	for unit in command_units:
		if is_instance_valid(unit) and unit.owner_team != friendly_team:
			return true
	return false

func can_be_captured_by_team(team: int) -> bool:
	"""Проверяет, может ли команда захватить этот гекс"""
	# Нельзя захватывать если уже принадлежит этой команде
	if team_owner == team:
		return false
	
	# Нельзя захватывать если есть вражеские командные юниты
	if has_enemy_command_units(team):
		return false
		
	return true

func start_capture(team: int) -> void:
	"""Начинает процесс захвата гекса командой"""
	capturing_team = team
	capture_progress = 0.0
	print("🏁 ЗАХВАТ: Команда ", team, " начала захват гекса ", position)

func update_capture_progress(delta: float, capture_speed: float) -> bool:
	"""
	Обновляет прогресс захвата
	Возвращает true если захват завершен
	"""
	if capturing_team == -1:
		return false
		
	capture_progress += delta * capture_speed
	
	if capture_progress >= 1.0:
		complete_capture()
		return true
		
	return false

func complete_capture() -> void:
	"""Завершает захват гекса"""
	var old_owner = team_owner
	team_owner = capturing_team
	capturing_team = -1
	capture_progress = 0.0
	
	print("✅ ЗАХВАТ: Гекс ", position, " захвачен! Владелец изменился с команды ", old_owner, " на команду ", team_owner)

func reset_capture() -> void:
	"""Сбрасывает процесс захвата"""
	capturing_team = -1
	capture_progress = 0.0
	print("❌ ЗАХВАТ: Процесс захвата гекса ", position, " прерван") 
