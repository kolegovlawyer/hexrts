class_name PlayerProfile extends Node

var PlayerId : int
var Team : GameTypes.Teams
var available_units = {}

func init(player:int, team:GameTypes.Teams):
	PlayerId = player
	Team = team
	return self # GOD DAYM

func deserialize():
	return {"PlayerId":PlayerId, "Team":Team}

func give_units(): # TODO : функция костыль, сделать нормальное разделение на личное и боевые юниты
	available_units = {
	
	}
