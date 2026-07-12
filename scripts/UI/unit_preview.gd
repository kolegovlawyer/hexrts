class_name UnitPreview extends PanelContainer

var unit : BaseUnit:
	set(value):
		unit = value
		update_visual()

@onready var sprite = get_node("MainRack/SpriteIcon")
@onready var rank = get_node("MainRack/StatusBoard/RankIcon")
@onready var hp_bar = get_node("MainRack/StatusBoard/Control/BarsDeck/HPBar")
@onready var shield_bar = get_node("MainRack/StatusBoard/Control/BarsDeck/ShieldBar")
@onready var name_label = get_node("MainRack/NameLabel")

var _style_normal: StyleBox
var _style_selected: StyleBoxFlat
var _rack_selected: bool = false

func _ready() -> void:
	_style_normal = get_theme_stylebox("panel")
	if _style_normal == null:
		_style_normal = StyleBoxEmpty.new()
	_style_selected = StyleBoxFlat.new()
	_style_selected.bg_color = Color(0, 0, 0, 0)
	_style_selected.set_border_width_all(2)
	_style_selected.border_color = GameTypes.own_color
	connect("gui_input", handle_input)
	call_deferred("update_visual")
	call_deferred("_delete_if_unbound")


func _delete_if_unbound() -> void:
	if not is_instance_valid(unit):
		queue_free()

func handle_input(event):
	if not is_instance_valid(unit):
		queue_free()
		return
	if event is InputEventMouseButton and event.button_index == 1 and event.pressed == false:
		if Input.is_key_pressed(KEY_SHIFT):
			Handlers.UnitSelectionHandler.add_selected(unit)
			get_viewport().set_input_as_handled()
			return
		Handlers.UIHandler.camera.position = unit.position
		Handlers.UnitSelectionHandler.clear_selection()
		Handlers.UnitSelectionHandler.add_selected(unit)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == 1 and event.pressed == true:
		get_viewport().set_input_as_handled()

func set_rack_selected(is_selected: bool) -> void:
	_rack_selected = is_selected
	if not is_node_ready():
		return
	if is_selected:
		add_theme_stylebox_override("panel", _style_selected)
	else:
		add_theme_stylebox_override("panel", _style_normal)

func update_visual() -> void:
	if not is_instance_valid(unit):
		return
	if not is_node_ready():
		return

	var client_unit := unit as BaseUnitClient
	if client_unit == null:
		return

	if unit.preset_icon_path != "":
		var preset_texture: Texture2D = load(unit.preset_icon_path) as Texture2D
		if preset_texture:
			sprite.texture = preset_texture
	else:
		var unit_sprite: Sprite2D = unit.get_node_or_null("%UnitSelfSprite")
		if unit_sprite and unit_sprite.texture:
			sprite.texture = unit_sprite.texture

	var preview_cost: int = unit.preset_cost
	if preview_cost <= 0:
		preview_cost = UnitPresetBalance.calculate_cost(
			UnitPresetBalance.default_stats(), unit.is_command_unit()
		)
	var icon_scale: float = UnitPresetBalance.visual_scale_for_cost(
		preview_cost, unit.is_command_unit()
	)
	sprite.scale = Vector2(icon_scale, icon_scale)

	if rank:
		# Фиксированный размер: иначе большая текстура ранга раздувает StatusBoard и бары.
		rank.custom_minimum_size = Vector2(18, 18)
		rank.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rank.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if unit.rank <= 0:
			rank.hide()
		else:
			var rank_path := "res://assets/ranks/rank-%d.png" % clampi(
				unit.rank, 1, UnitPresetBalance.RANK_THRESHOLDS.size()
			)
			var rank_tex: Texture2D = load(rank_path) as Texture2D
			if rank_tex:
				rank.texture = rank_tex
			rank.show()

	if client_unit.has_method("get_display_name"):
		name_label.text = client_unit.get_display_name()
	else:
		name_label.text = "Боец"

	hp_bar.max_value = unit.max_health
	shield_bar.max_value = unit.max_shield
	shield_bar.visible = unit.max_shield > 0

	update_vitals()
	set_rack_selected(_rack_selected)
	visible = true

func update_vitals() -> void:
	if not is_instance_valid(unit) or not is_node_ready():
		return

	var client_unit := unit as BaseUnitClient
	if client_unit == null:
		return

	var current_health: int = client_unit.get_current_health()
	var current_shield: int = client_unit.get_current_shield()
	var max_hp: int = unit.max_health
	var max_sh: int = unit.max_shield

	hp_bar.max_value = max_hp
	hp_bar.value = current_health

	var health_percent := float(current_health) / float(max_hp) if max_hp > 0 else 0.0
	if health_percent > 0.7:
		hp_bar.modulate = Color.GREEN
	elif health_percent > 0.3:
		hp_bar.modulate = Color.YELLOW
	else:
		hp_bar.modulate = Color.RED

	shield_bar.visible = max_sh > 0
	if max_sh <= 0:
		return

	shield_bar.max_value = max_sh
	shield_bar.value = current_shield

	var shield_percent := float(current_shield) / float(max_sh) if max_sh > 0 else 0.0
	if shield_percent > 0.7:
		shield_bar.modulate = Color.CYAN
	elif shield_percent > 0.3:
		shield_bar.modulate = Color.MAGENTA
	elif shield_percent > 0:
		shield_bar.modulate = Color.ORANGE
	else:
		shield_bar.modulate = Color.TRANSPARENT
