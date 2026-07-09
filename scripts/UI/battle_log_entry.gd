class_name BattleLogEntry
extends PanelContainer

signal clicked(hex_tile: Vector2i)

var hex_tile: Vector2i = Vector2i.ZERO

@onready var _label: RichTextLabel = $RichTextLabel

var _style_normal: StyleBoxFlat
var _style_hover: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0, 0, 0, 0)
	_style_hover = StyleBoxFlat.new()
	_style_hover.bg_color = Color(0.25, 0.28, 0.38, 0.55)
	add_theme_stylebox_override("panel", _style_normal)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func setup(bbcode_text: String, tile: Vector2i) -> void:
	hex_tile = tile
	if _label:
		_label.text = bbcode_text
	elif has_node("RichTextLabel"):
		($RichTextLabel as RichTextLabel).text = bbcode_text


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			clicked.emit(hex_tile)
			accept_event()


func _on_mouse_entered() -> void:
	add_theme_stylebox_override("panel", _style_hover)


func _on_mouse_exited() -> void:
	add_theme_stylebox_override("panel", _style_normal)
