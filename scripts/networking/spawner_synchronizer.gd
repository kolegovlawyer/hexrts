extends MultiplayerSpawner

func _ready():
	spawn_function = custom_spawner
	Handlers.NetworkSpawner = self
	
func _exit_tree():
	Handlers.NetworkSpawner = null

func custom_spawner(data:Dictionary):
	var unit = load(data["path"]).instantiate()
	
	# НОВАЯ СИСТЕМА: Назначаем правильный скрипт в зависимости от роли
	var is_command_unit = data["path"].ends_with("command_unit.tscn")
	
	if is_multiplayer_authority():
		# Серверная инстанция
		if is_command_unit:
			# Для командных юнитов используем специальный скрипт
			var server_script = load("res://scripts/command_unit_server.gd")
			unit.set_script(server_script)
			Handlers.dprint("🖥️ SPAWNER: command server script %s" % unit.name)
		else:
			# Для обычных юнитов
			var server_script = load("res://scripts/base_unit_server.gd")
			unit.set_script(server_script)
			Handlers.dprint("🖥️ SPAWNER: server script %s" % unit.name)
	else:
		# Клиентская инстанция
		if is_command_unit:
			var client_script = load("res://scripts/command_unit_client.gd")
			unit.set_script(client_script)
			Handlers.dprint("💻 SPAWNER: command client script %s" % unit.name)
		else:
			var client_script = load("res://scripts/base_unit_client.gd")
			unit.set_script(client_script)
			Handlers.dprint("💻 SPAWNER: client script %s" % unit.name)
	
	# ИСПРАВЛЕНИЕ: Безопасная загрузка профиля юнита
	var unit_profile = null
	if data.has("resource_info") and data["resource_info"] != null and data["resource_info"] != "":
		unit_profile = load(data["resource_info"])
	
	unit.position = data["position"]
	
	# Устанавливаем профиль только если он успешно загружен
	if unit_profile:
		unit.unit_profile = unit_profile
	
	# ИСПРАВЛЕНИЕ: Устанавливаем owner_id если предоставлен
	if data.has("owner_id"):
		unit.owner_id = data["owner_id"]
		Handlers.dprint("✅ SPAWNER: owner_id %s for %s" % [unit.owner_id, unit.name])
	else:
		Handlers.dprint("⚠️ SPAWNER: no owner_id for %s" % unit.name)

	_apply_spawn_appearance(unit, data)

	if data.has("vision_radius") and unit is BaseUnit:
		(unit as BaseUnit).vision_radius = data["vision_radius"]

	return unit


func _apply_spawn_appearance(unit: Node, data: Dictionary) -> void:
	if not data.has("preset_icon_path"):
		return
	if not unit is BaseUnit:
		return
	var base_unit := unit as BaseUnit
	base_unit.preset_display_name = str(data.get("preset_display_name", ""))
	base_unit.preset_instance_number = int(data.get("preset_instance_number", 0))
	base_unit.preset_icon_path = str(data.get("preset_icon_path", ""))
