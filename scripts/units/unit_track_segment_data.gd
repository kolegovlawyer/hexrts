class_name UnitTrackSegmentData
extends RefCounted

## Легковесные данные сегмента следа (без Node2D / Line2D).

var from_global: Vector2 = Vector2.ZERO
var to_global: Vector2 = Vector2.ZERO
var created_at: float = 0.0
var settings: UnitTrackSettings
var fog_visibility: float = 1.0
## Кэш цвета отрисовки: пересчёт только при заметном изменении fade / fog.
var cached_fade: float = -1.0
var cached_draw_color: Color = Color.TRANSPARENT
var color_dirty: bool = true
