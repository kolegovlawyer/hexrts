extends MultiplayerSpawner

func _ready():
	spawn_function = custom_spawner
	Handlers.NetworkSpawner = self
	
func _exit_tree():
	Handlers.NetworkSpawner = null

func custom_spawner(data:Dictionary):
	var unit = load(data["path"]).instantiate()
	var unit_profile = load(data["resource_info"])
	#unit.set_script(GameTypes.get_unit_script_by_class(unit_profile.unit_type))
	unit.position = data["position"]
	unit.unit_profile = unit_profile
	#unit.owner_id = data["owner_id"] # <- Надо переписать код BaseUnit, пока что айдишник меняется после появления юнита у всех клиентов
	return unit
