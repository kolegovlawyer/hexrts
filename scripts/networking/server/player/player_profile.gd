class_name PlayerProfile extends Node

var PlayerId : int
var team: GameTypes.Teams
var available_units = {}

func init(player: int, team_id: GameTypes.Teams) -> PlayerProfile:
	PlayerId = player
	team = team_id
	return self # GOD DAYM

func deserialize():
	return {"PlayerId":PlayerId, "Team":team}

func give_units(): # TODO : функция костыль, сделать нормальное разделение на личное и боевые юниты
	available_units = {
	
	}
