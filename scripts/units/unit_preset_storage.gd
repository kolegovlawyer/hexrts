class_name UnitPresetStorage
extends RefCounted

const SAVE_PATH := "user://presets/unit_presets.json"
const FILE_VERSION := 1


static func get_save_path_absolute() -> String:
	return ProjectSettings.globalize_path(SAVE_PATH)


static func save_presets(presets: Array) -> bool:
	var preset_dicts: Array = []
	for item in presets:
		if item is UnitPreset:
			preset_dicts.append(item.to_dict())

	var payload := {
		"version": FILE_VERSION,
		"presets": preset_dicts,
	}

	var json_text := JSON.stringify(payload, "\t")
	if not _ensure_presets_dir():
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("UnitPresetStorage: не удалось открыть файл для записи: %s" % SAVE_PATH)
		return false

	file.store_string(json_text)
	return true


static func load_presets() -> Variant:
	if not FileAccess.file_exists(SAVE_PATH):
		push_warning("UnitPresetStorage: файл не найден: %s" % SAVE_PATH)
		return null

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("UnitPresetStorage: не удалось открыть файл для чтения: %s" % SAVE_PATH)
		return null

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error("UnitPresetStorage: ошибка парсинга JSON: %s" % json.get_error_message())
		return null

	var root = json.data
	if typeof(root) != TYPE_DICTIONARY:
		push_error("UnitPresetStorage: корневой элемент JSON должен быть объектом")
		return null

	var preset_entries: Array = root.get("presets", [])
	if typeof(preset_entries) != TYPE_ARRAY:
		push_error("UnitPresetStorage: поле presets должно быть массивом")
		return null

	var loaded_by_id: Dictionary = {}
	var skipped_count := 0
	for entry in preset_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			skipped_count += 1
			continue
		var preset: UnitPreset = UnitPreset.from_dict(entry)
		if preset == null:
			skipped_count += 1
			push_warning("UnitPresetStorage: пропущен невалидный пресет: %s" % str(entry))
			continue
		if preset.preset_id == "":
			preset.preset_id = "imported_%d" % loaded_by_id.size()
		loaded_by_id[preset.preset_id] = preset

	if skipped_count > 0 and loaded_by_id.is_empty() and not preset_entries.is_empty():
		push_error("UnitPresetStorage: все пресеты в файле невалидны")
		return null

	return loaded_by_id.values()


static func _ensure_presets_dir() -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("UnitPresetStorage: не удалось открыть user://")
		return false
	if dir.dir_exists("presets"):
		return true
	if dir.make_dir_recursive("presets") != OK:
		push_error("UnitPresetStorage: не удалось создать папку user://presets")
		return false
	return true
