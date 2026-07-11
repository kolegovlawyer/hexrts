extends Node

var enemy_color = Color("#FF7D7D")
var enemy_hover_color = Color("#F74B4B")
var own_color = Color("#9BF985")
var own_hover_color = Color("#70DB56")
var own_selected_color = Color("#FFFFFF")
var ally_color = Color("#11D4F4")
var hit_flash_color = Color("#FFB966")

@onready var UnitUiThemes = GlobalUiThemes.new()

enum OrderTypes { # MUST BE NOT NULL
	MOVE_FORWARD=1,
	MOVE_BACK=2,
	MOVE_BY_ROAD=3, # I think its ok for infantry to use like fast move
	UNLOAD=4,
	LAND=5,
	STOP=6,
	ATTACK_INDIRECT=7,
	ATTACK_DIRECT=8,
}


enum Teams {
	TEAM_A,
	TEAM_B
}

enum ServerPlayerId {
	TEAM_A=2,
	TEAM_B=3
}

enum GameLayers {
	GROUND=1,
	FOREST=10
}

enum TeamLayers {
	TEAM_A=5,
	TEAM_B=6
}

enum UnitClass {
  ARMORED_VEHICLE=1,
  LIGHT_VEHICLE=2,
  INFANTRY=3,
  HELICOPTER=4,
  PLANE=5,
}

enum TargetClass {
  ARMORED_VEHICLE=1,
  LIGHT_VEHICLE=2,
  INFANTRY=3,
  HELICOPTER=4,
  PLANE=5,
  INDERECT=10,
}

# Veri veri nice
func get_unit_script_by_class(unit_class:UnitClass):
	pass
	#match unit_class:
		#UnitClass.ARMORED_VEHICLE:
			#return preload("res://Scripts/Units/Ground/GroundVehicleUnit.gd")
		#UnitClass.LIGHT_VEHICLE:
			#return preload("res://Scripts/Units/Ground/GroundVehicleUnit.gd")
		#UnitClass.INFANTRY:
			#return preload("res://Scripts/Units/Ground/InfantryUnit.gd")
		#UnitClass.HELICOPTER:
			#return preload("res://Scripts/Units/Air/HelicopterUnit.gd")
		#_:
			#return preload("res://Scripts/Units/BaseUnit.gd")

class GlobalUiThemes extends Resource:
	pass
	#var owned = preload("res://Prefabs/Theme/Owned_UI_Label.tres")
	#var ally =  preload("res://Prefabs/Theme/Allies_UI_Label_theme.tres")
	#var enemy = preload("res://Prefabs/Theme/Enemy_UI_Label_theme.tres")
