extends Node

signal presets_changed(player_id: int)

var _presets_by_player: Dictionary = {}


func ensure_player_presets(player_id: int) -> Array:
	if not _presets_by_player.has(player_id):
		_presets_by_player[player_id] = [
			UnitPreset.create_default(),
			_create_command_default(),
		]
	else:
		_ensure_standard_presets(_presets_by_player[player_id])
	return _presets_by_player[player_id]


func get_presets(player_id: int) -> Array:
	return ensure_player_presets(player_id)


func get_preset_by_id(player_id: int, preset_id: String) -> UnitPreset:
	for preset in get_presets(player_id):
		if preset.preset_id == preset_id:
			return preset
	return null


func save_preset(player_id: int, preset: UnitPreset) -> UnitPreset:
	var presets: Array = ensure_player_presets(player_id)
	if preset.preset_id == "":
		preset.preset_id = _generate_preset_id()
		presets.append(preset)
	else:
		var replaced := false
		for i in presets.size():
			if presets[i].preset_id == preset.preset_id:
				presets[i] = preset
				replaced = true
				break
		if not replaced:
			presets.append(preset)
	presets_changed.emit(player_id)
	return preset


func _generate_preset_id() -> String:
	return "preset_%d_%d" % [Time.get_ticks_msec(), randi() % 10000]


func _ensure_standard_presets(presets: Array) -> void:
	var has_fighter := false
	var has_command := false
	for i in presets.size():
		var preset: UnitPreset = presets[i]
		if preset.preset_id == "default":
			preset.preset_id = "standard_fighter"
			preset.preset_name = UnitPresetBalance.default_preset_name()
		if preset.preset_id == "standard_fighter":
			has_fighter = true
		elif preset.preset_id == "standard_command":
			has_command = true
	if not has_fighter:
		presets.insert(0, UnitPreset.create_default())
	if not has_command:
		var command_index := mini(1, presets.size())
		presets.insert(command_index, _create_command_default())


func _create_command_default() -> UnitPreset:
	var preset := UnitPreset.new()
	preset.preset_id = "standard_command"
	preset.preset_name = "КШМ"
	preset.is_command = true
	preset.apply_stats_dict(UnitPresetBalance.default_stats())
	return preset


var _instance_counters: Dictionary = {}


func next_instance_number(player_id: int, preset_id: String) -> int:
	var key := "%d:%s" % [player_id, preset_id if preset_id != "" else "default"]
	var current: int = int(_instance_counters.get(key, 0)) + 1
	_instance_counters[key] = current
	return current


func export_presets_to_disk(player_id: int) -> bool:
	var presets: Array = get_presets(player_id)
	return UnitPresetStorage.save_presets(presets)


func import_presets_from_disk(player_id: int) -> bool:
	var loaded_result = UnitPresetStorage.load_presets()
	if loaded_result == null:
		return false

	var loaded_presets: Array = loaded_result
	_presets_by_player[player_id] = loaded_presets
	presets_changed.emit(player_id)
	return true
