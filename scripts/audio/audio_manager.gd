extends Node
## Клиентский менеджер звука движения армии.
## Headless-сервер полностью бездействует и не загружает аудио.

# --- Константы движения / слоёв ---
const MOVE_SOUND_SATURATION := 15.0
const SMOOTH_SPEED := 2.0
const POSITIONAL_LIMIT := 8
const DUCK_DB := -6.0
const FADE_IN_SEC := 0.4
const FADE_OUT_SEC := 0.3
const MOVE_ENTER_SPEED := 5.0 ## px/s — порог входа в «движение»
const MOVE_ENTER_HOLD := 0.1 ## s
const MOVE_EXIT_SPEED := 2.0 ## px/s — порог выхода
const MOVE_EXIT_HOLD := 0.3 ## s
const LINEAR_SILENCE := 0.0001
const DUCK_SMOOTH_SPEED := 4.0
const MOVE_STREAM_PATH := "res://assets/audio/disel_engine.ogg"
const BUS_UNITS := "Units"

var _enabled: bool = false
var _stream: AudioStream = null
var _layer1: AudioStreamPlayer = null
var _pool: Array[AudioStreamPlayer2D] = []

## Трекинг позиции/скорости по instance_id юнита.
var _tracks: Dictionary = {} # int -> Dictionary

## Слот пула: unit, player, linear_vol, target_vol, pitch_jitter, fading_out
var _slots: Array[Dictionary] = []

var _layer1_loudness: float = 0.0
var _duck_linear: float = 1.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_physics_process(false)
		Handlers.dprint("AudioManager: headless — audio disabled")
		return
	_init_audio()


func _init_audio() -> void:
	_stream = load(MOVE_STREAM_PATH) as AudioStream
	if _stream == null:
		Handlers.dprint("AudioManager: failed to load", MOVE_STREAM_PATH)
		set_physics_process(false)
		return
	# Import должен выставить loop; дублируем на инстансе на случай до reimport.
	if _stream is AudioStreamOggVorbis:
		(_stream as AudioStreamOggVorbis).loop = true
	elif _stream is AudioStreamMP3:
		(_stream as AudioStreamMP3).loop = true

	_layer1 = AudioStreamPlayer.new()
	_layer1.name = "MoveLayer1"
	_layer1.stream = _stream
	_layer1.bus = BUS_UNITS
	_layer1.volume_db = _linear_to_player_db(LINEAR_SILENCE)
	add_child(_layer1)
	_layer1.play()

	_pool.clear()
	_slots.clear()
	for i in POSITIONAL_LIMIT:
		var p := AudioStreamPlayer2D.new()
		p.name = "MovePositional_%d" % i
		p.stream = _stream
		p.bus = BUS_UNITS
		p.volume_db = _linear_to_player_db(LINEAR_SILENCE)
		p.max_distance = 2000.0
		add_child(p)
		_pool.append(p)
		_slots.append({
			"unit": null,
			"player": p,
			"linear_vol": 0.0,
			"target_vol": 0.0,
			"pitch_jitter": 1.0,
			"fading_out": false,
		})

	_enabled = true
	Handlers.dprint("AudioManager: initialized, pool=", POSITIONAL_LIMIT)


func _physics_process(delta: float) -> void:
	if not _enabled or delta <= 0.0:
		return

	var camera: Camera2D = _get_camera()
	var visible_rect := Rect2()
	var screen_center := Vector2.ZERO
	var has_camera := camera != null and is_instance_valid(camera)
	if has_camera:
		if camera.has_method("get_visible_world_rect"):
			visible_rect = camera.get_visible_world_rect()
		else:
			var half := get_viewport().get_visible_rect().size / (2.0 * camera.zoom)
			visible_rect = Rect2(camera.global_position - half, half * 2.0)
		screen_center = camera.global_position
		_update_pool_max_distance(visible_rect)

	var tree := get_tree()
	if tree == null:
		return

	var units: Array = tree.get_nodes_in_group("units")
	var alive_ids: Dictionary = {}
	var moving_in_view: int = 0
	var moving_units: Array[BaseUnit] = []

	for node in units:
		if not is_instance_valid(node) or not (node is BaseUnit):
			continue
		var unit := node as BaseUnit
		var id := unit.get_instance_id()
		alive_ids[id] = true
		var track: Dictionary = _tracks.get(id, {})
		var pos := unit.global_position
		var observed_speed := 0.0
		if track.has("last_pos"):
			observed_speed = pos.distance_to(track["last_pos"]) / delta
		var is_moving: bool = bool(track.get("is_moving", false))
		var enter_t: float = float(track.get("enter_t", 0.0))
		var exit_t: float = float(track.get("exit_t", 0.0))

		if is_moving:
			if observed_speed < MOVE_EXIT_SPEED:
				exit_t += delta
				if exit_t >= MOVE_EXIT_HOLD:
					is_moving = false
					enter_t = 0.0
					exit_t = 0.0
			else:
				exit_t = 0.0
		else:
			if observed_speed > MOVE_ENTER_SPEED:
				enter_t += delta
				if enter_t >= MOVE_ENTER_HOLD:
					is_moving = true
					enter_t = 0.0
					exit_t = 0.0
			else:
				enter_t = 0.0

		_tracks[id] = {
			"last_pos": pos,
			"is_moving": is_moving,
			"enter_t": enter_t,
			"exit_t": exit_t,
			"observed_speed": observed_speed,
			"unit": unit,
		}

		if is_moving:
			moving_units.append(unit)
			if has_camera and visible_rect.has_point(pos):
				moving_in_view += 1

	# Убрать треки мёртвых юнитов
	var dead_ids: Array = []
	for id in _tracks.keys():
		if not alive_ids.has(id):
			dead_ids.append(id)
	for id in dead_ids:
		_tracks.erase(id)

	_update_positional_layer(delta, moving_units, screen_center, has_camera)
	_update_layer1(delta, moving_in_view)


func _update_layer1(delta: float, moving_in_view: int) -> void:
	var target := clampf(float(moving_in_view) / MOVE_SOUND_SATURATION, 0.0, 1.0)
	_layer1_loudness = move_toward(_layer1_loudness, target, delta * SMOOTH_SPEED)

	var active_positional := _count_active_positional()
	var duck_target := 1.0
	if active_positional >= int(POSITIONAL_LIMIT / 2.0):
		duck_target = db_to_linear(DUCK_DB)
	_duck_linear = move_toward(_duck_linear, duck_target, delta * DUCK_SMOOTH_SPEED)

	var linear_vol := _layer1_loudness * _duck_linear
	_layer1.volume_db = _linear_to_player_db(linear_vol)
	_layer1.pitch_scale = lerpf(0.95, 1.05, _layer1_loudness)


func _update_positional_layer(
		delta: float,
		moving_units: Array[BaseUnit],
		screen_center: Vector2,
		has_camera: bool
	) -> void:
	# Кандидаты: движущиеся ∩ выделенные
	var selected: Array = []
	if Handlers.UnitSelectionHandler != null:
		selected = Handlers.UnitSelectionHandler.selected_units

	var selected_set: Dictionary = {}
	for s in selected:
		if is_instance_valid(s):
			selected_set[s.get_instance_id()] = true

	var candidates: Array[Dictionary] = []
	for unit in moving_units:
		if not is_instance_valid(unit):
			continue
		if not selected_set.has(unit.get_instance_id()):
			continue
		var dist_sq := 0.0
		if has_camera:
			dist_sq = unit.global_position.distance_squared_to(screen_center)
		candidates.append({"unit": unit, "dist_sq": dist_sq})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["dist_sq"]) < float(b["dist_sq"])
	)

	var desired: Dictionary = {} # instance_id -> BaseUnit
	var limit := mini(candidates.size(), POSITIONAL_LIMIT)
	for i in limit:
		var u: BaseUnit = candidates[i]["unit"]
		desired[u.get_instance_id()] = u

	# Освободить слоты, юниты которых больше не в desired
	for slot in _slots:
		var assigned: Variant = slot["unit"]
		if assigned == null:
			continue
		if not is_instance_valid(assigned):
			_begin_fade_out(slot)
			slot["unit"] = null
			continue
		var uid: int = (assigned as Node).get_instance_id()
		if not desired.has(uid):
			_begin_fade_out(slot)
			slot["unit"] = null

	# Назначить свободные слоты новым кандидатам
	for uid in desired.keys():
		if _find_slot_for_unit_id(uid) >= 0:
			continue
		var free_idx := _find_free_slot()
		if free_idx < 0:
			break
		var unit: BaseUnit = desired[uid]
		_assign_slot(free_idx, unit)

	# Обновить громкость / позицию / pitch
	for slot in _slots:
		var player: AudioStreamPlayer2D = slot["player"]
		var unit_ref: Variant = slot["unit"]
		var target_vol: float = float(slot["target_vol"])
		var linear_vol: float = float(slot["linear_vol"])

		if unit_ref != null and is_instance_valid(unit_ref):
			var unit := unit_ref as BaseUnit
			player.global_position = unit.global_position
			var track: Dictionary = _tracks.get(unit.get_instance_id(), {})
			var observed: float = float(track.get("observed_speed", 0.0))
			var max_speed := maxf(float(unit.move_speed_max), 1.0)
			var speed_ratio := clampf(observed / max_speed, 0.0, 1.5)
			var base_pitch := _base_pitch_for_unit(unit)
			player.pitch_scale = (
				base_pitch
				* lerpf(0.9, 1.15, speed_ratio)
				* float(slot["pitch_jitter"])
			)

		var fade_speed := 1.0 / FADE_IN_SEC if target_vol > linear_vol else 1.0 / FADE_OUT_SEC
		linear_vol = move_toward(linear_vol, target_vol, delta * fade_speed)
		slot["linear_vol"] = linear_vol
		player.volume_db = _linear_to_player_db(linear_vol)

		if bool(slot["fading_out"]) and linear_vol <= LINEAR_SILENCE:
			if player.playing:
				player.stop()
			slot["fading_out"] = false
			slot["target_vol"] = 0.0
			slot["linear_vol"] = 0.0


func _assign_slot(idx: int, unit: BaseUnit) -> void:
	var slot: Dictionary = _slots[idx]
	var player: AudioStreamPlayer2D = slot["player"]
	slot["unit"] = unit
	slot["target_vol"] = 1.0
	slot["fading_out"] = false
	slot["pitch_jitter"] = randf_range(0.95, 1.05)
	player.global_position = unit.global_position
	if not player.playing:
		player.play()
	Handlers.dprint("AudioManager: assign positional to", unit.name)


func _begin_fade_out(slot: Dictionary) -> void:
	slot["target_vol"] = 0.0
	slot["fading_out"] = true


func _find_slot_for_unit_id(unit_id: int) -> int:
	for i in _slots.size():
		var assigned: Variant = _slots[i]["unit"]
		if assigned != null and is_instance_valid(assigned):
			if (assigned as Node).get_instance_id() == unit_id:
				return i
	return -1


func _find_free_slot() -> int:
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		# Свободен: нет юнита и не в процессе fade-out (или уже затих)
		if slot["unit"] != null:
			continue
		if bool(slot["fading_out"]) and float(slot["linear_vol"]) > LINEAR_SILENCE:
			continue
		return i
	return -1


func _count_active_positional() -> int:
	var n := 0
	for slot in _slots:
		if slot["unit"] != null and is_instance_valid(slot["unit"]):
			n += 1
		elif bool(slot["fading_out"]) and float(slot["linear_vol"]) > LINEAR_SILENCE:
			n += 1
	return n


func _base_pitch_for_unit(unit: BaseUnit) -> float:
	var scale := UnitPresetBalance.visual_scale_for_cost(
		unit.preset_cost, unit.is_command_unit()
	)
	var t := 0.0
	var span := UnitPresetBalance.SCALE_MAX - UnitPresetBalance.SCALE_MIN
	if span > 0.0:
		t = clampf(
			(scale - UnitPresetBalance.SCALE_MIN) / span,
			0.0,
			1.0
		)
	# Лёгкий ≈ 1.3, тяжёлый ≈ 0.8
	return lerpf(1.3, 0.8, t)


func _update_pool_max_distance(visible_rect: Rect2) -> void:
	var diag := visible_rect.size.length()
	var max_dist := maxf(diag * 0.75, 400.0)
	for p in _pool:
		p.max_distance = max_dist


func _get_camera() -> Camera2D:
	if Handlers.UIHandler != null and Handlers.UIHandler.camera != null:
		return Handlers.UIHandler.camera as Camera2D
	var viewport := get_viewport()
	if viewport != null:
		return viewport.get_camera_2d()
	return null


func _linear_to_player_db(linear: float) -> float:
	return linear_to_db(maxf(linear, LINEAR_SILENCE))


# --- API громкости шин (для будущего меню настроек) ---

func set_bus_volume_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		Handlers.dprint("AudioManager: unknown bus", bus_name)
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, LINEAR_SILENCE)))


func set_master_volume(linear: float) -> void:
	set_bus_volume_linear("Master", linear)


func set_sfx_volume(linear: float) -> void:
	set_bus_volume_linear("SFX", linear)


func set_music_volume(linear: float) -> void:
	set_bus_volume_linear("Music", linear)


func set_ui_volume(linear: float) -> void:
	set_bus_volume_linear("UI", linear)
