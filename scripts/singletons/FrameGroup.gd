class_name FrameGroup extends Node

var num_groups : int
var groups : Dictionary = {} 

func _ready():
	Handlers.FrameGroupHandler = self
	num_groups = ProjectSettings.get_setting("physics/common/physics_ticks_per_second")
	populate_groups()
  
func _exit_tree():
	Handlers.FrameGroupHandler = null

func populate_groups() -> void: 
	for i in range(num_groups):
		groups[i] = []

func add_to_framegroup(unit:BaseUnit) -> int:
	var min_group := 0
	var min_items := len(groups[0])
	for i in groups:
		if len(groups[i]) < min_items:
			min_group = i
			min_items = len(groups[i])
	groups[min_group].append(unit)
	return min_group

func remove_from_framegroup(unit:Node3D, group_num:int) -> void:
	groups[group_num].pop_at(groups[group_num].find(unit))
