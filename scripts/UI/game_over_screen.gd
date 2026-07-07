class_name GameOverScreen
extends Control

@onready var title_label: Label = %TitleLabel
@onready var reason_label: Label = %ReasonLabel
@onready var lobby_button: Button = %LobbyButton

const REASON_TEXT: Dictionary = {
	"vp_threshold": "Набрано достаточно очков победы",
	"domination": "Доминирование на карте",
	"time_limit": "Истекло время матча",
	"fob_destroyed": "База противника уничтожена",
}


func _ready() -> void:
	lobby_button.pressed.connect(_on_lobby_button_pressed)


func setup(is_winner: bool, reason: String, is_draw: bool = false) -> void:
	if is_draw:
		title_label.text = "Ничья"
	elif is_winner:
		title_label.text = "Победа!"
	else:
		title_label.text = "Поражение"
	reason_label.text = REASON_TEXT.get(reason, reason)


func _on_lobby_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
