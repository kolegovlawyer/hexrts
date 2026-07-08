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
		_migrate_legacy_preset_ids(_presets_by_player[player_id])
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


func delete_preset(player_id: int, preset_id: String) -> bool:
	if preset_id == "":
		return false
	var presets: Array = ensure_player_presets(player_id)
	for i in presets.size():
		if presets[i].preset_id == preset_id:
			presets.remove_at(i)
			presets_changed.emit(player_id)
			return true
	return false


func _migrate_legacy_preset_ids(presets: Array) -> void:
	for preset in presets:
		if preset.preset_id == "default":
			preset.preset_id = "standard_fighter"
			preset.preset_name = UnitPresetBalance.default_preset_name()


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


func get_local_player_id() -> int:
	if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
		return Handlers.TeamHandler.my_profile.PlayerId
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 1


func try_autoload_presets() -> bool:
	return import_presets_from_disk(get_local_player_id())
