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
			print("🖥️ SPAWNER: Назначен командный серверный скрипт для юнита ", unit.name)
		else:
			# Для обычных юнитов
			var server_script = load("res://scripts/base_unit_server.gd")
			unit.set_script(server_script)
			print("🖥️ SPAWNER: Назначен серверный скрипт для юнита ", unit.name)
	else:
		# Клиентская инстанция
		if is_command_unit:
			# Для командных юнитов пока используем обычный клиентский скрипт
			var client_script = load("res://scripts/base_unit_client.gd")
			unit.set_script(client_script)
			print("💻 SPAWNER: Назначен клиентский скрипт для командного юнита ", unit.name)
		else:
			var client_script = load("res://scripts/base_unit_client.gd")
			unit.set_script(client_script)
			print("💻 SPAWNER: Назначен клиентский скрипт для юнита ", unit.name)
	
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
		print("✅ SPAWNER: Установлен owner_id ", unit.owner_id, " для юнита ", unit.name)
	else:
		print("⚠️ SPAWNER: owner_id не предоставлен для юнита ", unit.name)
		
	return unit
