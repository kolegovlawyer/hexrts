class_name FOB_panel
extends PanelContainer

const UNIT_CARD_SCENE := preload("res://prefabs/ui/preset_unit_card.tscn")

@onready var units_board: HBoxContainer = $FobPanelMarginContainer/MainRack/UnitsBoard
@onready var undeploy_button: Button = %Undeploy


func _ready() -> void:
	UnitPresetManager.presets_changed.connect(_on_presets_changed)
	_rebuild_unit_cards()
	if undeploy_button:
		undeploy_button.pressed.connect(_on_undeploy_pressed)


func _exit_tree() -> void:
	if UnitPresetManager.presets_changed.is_connected(_on_presets_changed):
		UnitPresetManager.presets_changed.disconnect(_on_presets_changed)


func _on_presets_changed(_player_id: int) -> void:
	_rebuild_unit_cards()


func _get_player_id() -> int:
	if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
		return Handlers.TeamHandler.my_profile.PlayerId
	return 1


func _rebuild_unit_cards() -> void:
	for child in units_board.get_children():
		child.queue_free()

	for preset in UnitPresetManager.get_presets(_get_player_id()):
		var card := UNIT_CARD_SCENE.instantiate() as PresetUnitCard
		if card == null:
			continue
		units_board.add_child(card)
		card.setup(preset)


func _on_undeploy_pressed() -> void:
	if Handlers.UnitSelectionHandler == null:
		return
	var selected: fob = Handlers.UnitSelectionHandler.selected_fob
	if selected == null or not is_instance_valid(selected):
		return
	if undeploy_button:
		undeploy_button.disabled = true
		undeploy_button.text = "Сворачивание..."
	selected.rpc_id(1, "request_undeploy")
