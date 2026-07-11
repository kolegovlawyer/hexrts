class_name CommandUnitClient extends BaseUnitClient

### КЛИЕНТСКАЯ ЛОГИКА КОМАНДНОГО ЮНИТА
# RPC-заглушки должны совпадать с command_unit_server.gd (порядок и сигнатуры),
# иначе checksum MultiplayerSpawner ломается и RPC попадают не в те методы.

@onready var capture_progress_bar = get_node("%CaptureProgress")

func _ready() -> void:
	is_command_unit_flag = true
	super._ready()
	# Клиент: только отображение — КШМ всегда ранг 5.
	rank = UnitPresetBalance.RANK_THRESHOLDS.size()
	update_rank_sprite()
	if capture_progress_bar:
		capture_progress_bar.hide()
		capture_progress_bar.value = 0.0

@rpc("any_peer", "reliable")
func client_start_capture_visual(_hex_position: Vector2i) -> void:
	if is_instance_valid(multiplayer) and owner_id == multiplayer.get_unique_id() and capture_progress_bar:
		capture_progress_bar.show()
		capture_progress_bar.value = 0.0
		capture_progress_bar.max_value = 100.0

@rpc("any_peer", "reliable")
func client_stop_capture_visual() -> void:
	if is_instance_valid(multiplayer) and owner_id == multiplayer.get_unique_id() and capture_progress_bar:
		capture_progress_bar.hide()
		capture_progress_bar.value = 0.0

@rpc("any_peer", "unreliable")
func client_update_capture_progress(progress_percent: float) -> void:
	if is_instance_valid(multiplayer) and owner_id == multiplayer.get_unique_id() and capture_progress_bar and capture_progress_bar.visible:
		capture_progress_bar.value = progress_percent


@rpc("any_peer", "reliable")
func request_deploy_fob() -> void:
	pass


@rpc("any_peer", "reliable")
func request_promote_to_command() -> void:
	pass
