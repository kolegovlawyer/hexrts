extends MultiplayerSpawner

func _ready():
	spawn_function = custom_spawner
	Handlers.NetworkSpawner = self
	
func _exit_tree():
	Handlers.NetworkSpawner = null

func custom_spawner(data:Dictionary):
	var unit = load(data["path"]).instantiate()
	
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
