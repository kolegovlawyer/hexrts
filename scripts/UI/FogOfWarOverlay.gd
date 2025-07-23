extends ColorRect

## ========================================================================
## FOG OF WAR OVERLAY - Компонент отображения тумана войны
## Использует координаты вьюпорта для корректного отображения
## ========================================================================

@onready var fog_manager = get_node("../../FogOfWarManager")

func _ready() -> void:
	# Устанавливаем размер ColorRect равным размеру вьюпорта
	custom_minimum_size = get_viewport().get_visible_rect().size
	size = custom_minimum_size
	
	# Подключаемся к изменению размера вьюпорта
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	
	# Устанавливаем привязки для растягивания по всему вьюпорту
	anchor_right = 1.0
	anchor_bottom = 1.0
	
	print("🎨 FOG_OVERLAY: Инициализирован с размером ", size)

func _on_viewport_size_changed() -> void:
	# Обновляем размер при изменении размера вьюпорта
	custom_minimum_size = get_viewport().get_visible_rect().size
	size = custom_minimum_size
	print("📐 FOG_OVERLAY: Размер обновлен до ", size)

# Используем _notification вместо _process для правильного таймирования
func _notification(what):
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		# Обновляем шейдер ПОСЛЕ того, как ColorRect обновил свою трансформацию
		var cam = get_viewport().get_camera_2d()
		if fog_manager and cam:
			fog_manager.update_shader_camera_data(cam) 
