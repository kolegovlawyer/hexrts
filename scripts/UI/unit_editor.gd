class_name UnitEditor
extends PanelContainer

const STAT_UI: Array[Dictionary] = [
	{
		"key": "health",
		"decrease_btn": "MarginContainer/MainContainer/VariableRack/EditorRack/VariableBoard/HealthVariable/HealthButtonIncrease",
		"increase_btn": "MarginContainer/MainContainer/VariableRack/EditorRack/VariableBoard/HealthVariable/HealthButtonDecrease",
		"progress_bar": "MarginContainer/MainContainer/VariableRack/EditorRack/BarBoard/HealtBar/HealthProgressBar",
		"value_label": "MarginContainer/MainContainer/VariableRack/EditorRack/BarBoard/HealtBar/HealthVarLabel",
	},
	{
		"key": "speed",
		"decrease_btn": "MarginContainer/MainContainer/VariableRack/EditorRack/VariableBoard/SpeedVariable/SpeedButtonIncrease",
		"increase_btn": "MarginContainer/MainContainer/VariableRack/EditorRack/VariableBoard/SpeedVariable/SpeedButtonDecrease",
		"progress_bar": "MarginContainer/MainContainer/VariableRack/EditorRack/BarBoard/SpeedBar/SpeedProgressBar",
		"value_label": "MarginContainer/MainContainer/VariableRack/EditorRack/BarBoard/SpeedBar/SpeedVarLabel",
	},
	{
		"key": "damage",
		"decrease_btn": "MarginContainer/MainContainer/VariableRack/EditorRack/VariableBoard/DamageVariable/DamageButtonIncrease",
		"increase_btn": "MarginContainer/MainContainer/VariableRack/EditorRack/VariableBoard/DamageVariable/ButtonDecrease",
		"progress_bar": "MarginContainer/MainContainer/VariableRack/EditorRack/BarBoard/DamageBar/DamageProgressBar",
		"value_label": "MarginContainer/MainContainer/VariableRack/EditorRack/BarBoard/DamageBar/DamageLabel",
	},
	{
		"key": "shield",
		"decrease_btn": "MarginContainer/MainContainer/VariableRack/EditorRack/VariableBoard/ShiledVariable/ShiledButtonIncrease",
		"increase_btn": "MarginContainer/MainContainer/VariableRack/EditorRack/VariableBoard/ShiledVariable/ShiledButtonDecrease",
		"progress_bar": "MarginContainer/MainContainer/VariableRack/EditorRack/BarBoard/ShiledBar/ShiledProgressBar",
		"value_label": "MarginContainer/MainContainer/VariableRack/EditorRack/BarBoard/ShiledBar/ShiledVarLabel",
	},
	{
		"key": "range",
		"decrease_btn": "MarginContainer/MainContainer/VariableRack/EditorRack/VariableBoard/RangeVariable/RangeButtonIncrease",
		"increase_btn": "MarginContainer/MainContainer/VariableRack/EditorRack/VariableBoard/RangeVariable/RangeButtonDecrease",
		"progress_bar": "MarginContainer/MainContainer/VariableRack/EditorRack/BarBoard/RangeBar/ProgressBar",
		"value_label": "MarginContainer/MainContainer/VariableRack/EditorRack/BarBoard/RangeBar/RangeVarLabel",
	},
]

@onready var unit_type_list: OptionButton = $MarginContainer/MainContainer/UnitTypeList
@onready var reset_button: Button = $MarginContainer/MainContainer/HeaderRack/ResetButton
@onready var save_button: Button = $MarginContainer/MainContainer/HeaderRack/SaveButton
@onready var delete_button: Button = $MarginContainer/MainContainer/HeaderRack/DeleteButton
@onready var command_button: Button = $MarginContainer/MainContainer/HeaderRack/ComandButton
@onready var name_field: LineEdit = $MarginContainer/MainContainer/HeaderRack/NameLabel
@onready var cost_label: Label = $MarginContainer/MainContainer/VariableRack/EditorRack/CostBoard/CostLabel
@onready var time_label: Label = $MarginContainer/MainContainer/VariableRack/EditorRack/CostBoard/TimeLabel
@onready var result_icon: TextureRect = $MarginContainer/MainContainer/VariableRack/EditorRack/CostBoard/ResultIcon
@onready var close_button: Button = $MarginContainer/MainContainer/VariableRack/EditorRack/CostBoard/CloseButton
@onready var save_presets_button: Button = $MarginContainer/MainContainer/PresetExportRack/SavePresetButton
@onready var load_presets_button: Button = $MarginContainer/MainContainer/PresetExportRack/LoadPresetButton

var _working_preset: UnitPreset = null
var _suppress_list_signal := false


func _ready() -> void:
	_configure_progress_bars()
	_connect_ui()
	_load_presets_into_list()
	_select_preset_index(0)


func _configure_progress_bars() -> void:
	for entry in STAT_UI:
		var bar: ProgressBar = get_node(entry.progress_bar)
		bar.min_value = UnitPresetBalance.STAT_MIN
		bar.max_value = UnitPresetBalance.STAT_MAX


func _connect_ui() -> void:
	reset_button.pressed.connect(_on_reset_pressed)
	save_button.pressed.connect(_on_save_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	command_button.pressed.connect(_on_command_pressed)
	close_button.pressed.connect(_on_close_pressed)
	save_presets_button.pressed.connect(_on_save_presets_pressed)
	load_presets_button.pressed.connect(_on_load_presets_pressed)
	unit_type_list.item_selected.connect(_on_preset_selected)

	for entry in STAT_UI:
		get_node(entry.decrease_btn).pressed.connect(_change_stat.bind(entry.key, -1))
		get_node(entry.increase_btn).pressed.connect(_change_stat.bind(entry.key, 1))


func _get_player_id() -> int:
	if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
		return Handlers.TeamHandler.my_profile.PlayerId
	return 1


func _load_presets_into_list() -> void:
	_suppress_list_signal = true
	unit_type_list.clear()
	var presets := UnitPresetManager.get_presets(_get_player_id())
	for i in presets.size():
		var preset: UnitPreset = presets[i]
		unit_type_list.add_item(preset.preset_name, i)
	unit_type_list.add_item("+ Новый пресет", presets.size())
	_suppress_list_signal = false


func _select_preset_index(index: int) -> void:
	var presets := UnitPresetManager.get_presets(_get_player_id())
	if index >= presets.size():
		_working_preset = UnitPreset.create_default()
		_working_preset.preset_id = ""
		_working_preset.preset_name = UnitPresetBalance.default_preset_name()
		_refresh_ui()
		return
	if index < 0:
		return
	_working_preset = presets[index].duplicate_preset()
	_working_preset.preset_id = presets[index].preset_id
	_refresh_ui()


func _on_preset_selected(index: int) -> void:
	if _suppress_list_signal:
		return
	_select_preset_index(index)


func _on_reset_pressed() -> void:
	if _working_preset == null:
		return
	_sync_name_from_field()
	_working_preset.apply_stats_dict(UnitPresetBalance.default_stats())
	_working_preset.is_command = false
	_refresh_ui()


func _on_command_pressed() -> void:
	if _working_preset == null:
		return
	_sync_name_from_field()
	_working_preset.is_command = not _working_preset.is_command
	_refresh_ui()


func _on_save_pressed() -> void:
	if _working_preset == null:
		return
	var trimmed_name := name_field.text.strip_edges()
	if trimmed_name == "":
		trimmed_name = UnitPresetBalance.default_preset_name()
	_working_preset.preset_name = trimmed_name
	var saved := UnitPresetManager.save_preset(_get_player_id(), _working_preset)
	_working_preset = saved.duplicate_preset()
	_working_preset.preset_id = saved.preset_id
	_load_presets_into_list()
	_suppress_list_signal = true
	var presets := UnitPresetManager.get_presets(_get_player_id())
	for i in presets.size():
		if presets[i].preset_id == saved.preset_id:
			unit_type_list.select(i)
			break
	_suppress_list_signal = false
	UnitPresetManager.export_presets_to_disk(_get_player_id())


func _on_delete_pressed() -> void:
	if _working_preset == null or _working_preset.preset_id == "":
		return
	var preset_id := _working_preset.preset_id
	if not UnitPresetManager.delete_preset(_get_player_id(), preset_id):
		return
	UnitPresetManager.export_presets_to_disk(_get_player_id())
	_load_presets_into_list()
	var presets := UnitPresetManager.get_presets(_get_player_id())
	if presets.is_empty():
		_select_preset_index(0)
		return
	_suppress_list_signal = true
	unit_type_list.select(0)
	_suppress_list_signal = false
	_select_preset_index(0)


func _on_close_pressed() -> void:
	queue_free()


func _on_save_presets_pressed() -> void:
	if _working_preset != null:
		_sync_name_from_field()
		var trimmed_name := name_field.text.strip_edges()
		if trimmed_name == "":
			trimmed_name = UnitPresetBalance.default_preset_name()
		_working_preset.preset_name = trimmed_name
		var saved := UnitPresetManager.save_preset(_get_player_id(), _working_preset)
		_working_preset = saved.duplicate_preset()
		_working_preset.preset_id = saved.preset_id

	if UnitPresetManager.export_presets_to_disk(_get_player_id()):
		print("UnitEditor: пресеты сохранены в ", UnitPresetStorage.get_save_path_absolute())
	else:
		print("UnitEditor: не удалось сохранить пресеты на диск")


func _on_load_presets_pressed() -> void:
	if not UnitPresetManager.import_presets_from_disk(_get_player_id()):
		print("UnitEditor: не удалось загрузить пресеты (файл отсутствует или повреждён)")
		return

	_load_presets_into_list()
	_select_preset_index(0)
	print("UnitEditor: пресеты загружены из ", UnitPresetStorage.get_save_path_absolute())


func _change_stat(stat_key: String, delta: int) -> void:
	if _working_preset == null:
		return
	_sync_name_from_field()
	var stats := _working_preset.get_stats_dict()
	var current := int(stats.get(stat_key, UnitPresetBalance.DEFAULT_STAT))
	if delta > 0 and not UnitPresetBalance.can_increase_stat(stats, stat_key):
		return
	stats[stat_key] = UnitPresetBalance.clamp_stat(current + delta)
	_working_preset.apply_stats_dict(stats)
	_refresh_ui()


func _sync_name_from_field() -> void:
	var current_name := name_field.text.strip_edges()
	if current_name != "":
		_working_preset.preset_name = current_name


func _refresh_ui() -> void:
	if _working_preset == null:
		return

	if name_field.text != _working_preset.preset_name:
		name_field.text = _working_preset.preset_name
	command_button.modulate = Color(1.0, 0.85, 0.35) if _working_preset.is_command else Color.WHITE
	delete_button.disabled = _working_preset.preset_id == ""

	var stats := _working_preset.get_stats_dict()
	for entry in STAT_UI:
		var value := int(stats.get(entry.key, UnitPresetBalance.DEFAULT_STAT))
		var bar: ProgressBar = get_node(entry.progress_bar)
		var label: Label = get_node(entry.value_label)
		bar.value = value
		label.text = str(value)

	var cost := _working_preset.get_cost()
	var spawn_time := _working_preset.get_spawn_time()
	cost_label.text = "Цена\n%d" % cost
	time_label.text = "Время\n%d" % int(ceil(spawn_time))
	result_icon.texture = UnitIconUtil.get_texture_for_preset(_working_preset)
