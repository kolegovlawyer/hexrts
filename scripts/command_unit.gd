extends BaseUnit
class_name CommandUnit

# Ссылка на слой карты
@onready var tile_map_layer = get_node("/root/Game/Map/TileMapLayer")

func _ready() -> void:
    super._ready()
    # Подключаем сигнал для проверки гекса при движении
    if is_multiplayer_authority():
        connect("position_changed", _on_position_changed)

# Функция для проверки текущего гекса
func check_current_hex() -> void:
    if not tile_map_layer:
        print("TileMapLayer not found!")
        return
        
    # Получаем позицию юнита в координатах тайлмапа
    var tile_pos = tile_map_layer.local_to_map(global_position)
    
    # Проверяем, есть ли гекс по этой позиции
    if tile_map_layer.has_hex_at(tile_pos):
        var hex = tile_map_layer.get_hex_at(tile_pos)
        print("Command unit is on hex: ", hex)
        # TODO: Добавить логику захвата гекса
    else:
        print("No hex found at position: ", tile_pos)

# Обработчик изменения позиции
func _on_position_changed() -> void:
    check_current_hex()

# Переопределяем _physics_process для добавления проверки гекса
func _physics_process(delta: float) -> void:
    super._physics_process(delta)
    if is_multiplayer_authority():
        check_current_hex() 