class_name PresetUnitCard
extends PanelContainer

var preset: UnitPreset = null


func _ready() -> void:
	connect("gui_input", _handle_input)


func setup(unit_preset: UnitPreset) -> void:
	preset = unit_preset
	_update_labels()


func _update_labels() -> void:
	if preset == null:
		return
	var name_label: Label = get_node_or_null("MarginContainer/MainRack/NameLabel")
	var attack_label: Label = get_node_or_null("MarginContainer/MainRack/AttackLabel")
	var range_label: Label = get_node_or_null("MarginContainer/MainRack/RangeLabel")
	var speed_label: Label = get_node_or_null("MarginContainer/MainRack/SpeedLabel")
	var health_label: Label = get_node_or_null("MarginContainer/MainRack/HealthLabel")
	var cost_label: Label = get_node_or_null("MarginContainer/MainRack/CostLabel")
	if name_label:
		name_label.text = preset.preset_name
	if attack_label:
		attack_label.text = "Атака: %d" % preset.damage
	if range_label:
		range_label.text = "Обзор: %d" % preset.range_stat
	if speed_label:
		speed_label.text = "Скорость: %d" % preset.speed
	if health_label:
		health_label.text = "Прочность: %d" % preset.health
	if cost_label:
		cost_label.text = "Цена: %d" % preset.get_cost()


func _handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_activate_card()
		get_viewport().set_input_as_handled()


func _activate_card() -> void:
	if preset == null:
		return
	if Handlers.UnitSelectionHandler == null or Handlers.UnitSelectionHandler.selected_fob == null:
		return

	var spawn_cost := preset.get_cost()
	var current_points := Handlers.UIHandler.get_current_recruitment_points()
	if current_points < spawn_cost:
		Handlers.UIHandler.show_insufficient_points_message()
		return

	var spawn_point := Handlers.UnitSelectionHandler.selected_fob.position
	var snapshot := preset.to_spawn_snapshot()
	Handlers.UnitSpawnHandler.rpc_id(
		1,
		"spawn_unit_with_validation",
		spawn_point,
		preset.get_unit_type(),
		spawn_cost,
		snapshot
	)
