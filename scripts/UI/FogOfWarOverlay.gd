extends ColorRect

@onready var fog_manager = get_node("../../FogOfWarManager")

func _ready() -> void:
	# Устанавливаем привязки ко всем краям экрана
	anchor_right = 1.0
	anchor_bottom = 1.0
	
	# Устанавливаем отступы в 0, чтобы ColorRect занимал всё пространство
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	
	# Подключаем сигнал изменения размера
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	
	print("🎨 FOG_OVERLAY: Инициализирован")

func _on_viewport_size_changed() -> void:
	# Сбрасываем отступы при изменении размера окна
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	print("📐 FOG_OVERLAY: Размер обновлен")
	var cam = get_viewport().get_camera_2d()
	if fog_manager and cam:
		fog_manager.update_shader_camera_data(cam)
#
#func _process(_delta):
	#var cam = get_viewport().get_camera_2d()
	#if fog_manager and cam:
		#fog_manager.update_shader_camera_data(cam)
