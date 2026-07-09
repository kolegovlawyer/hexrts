extends Node

## Глобальный шлюз логов (Handlers уже в autoload — LSP видит без перезагрузки).
const DEBUG_LOG_ENABLED := false

func dprint(
		p1: Variant = null,
		p2: Variant = null,
		p3: Variant = null,
		p4: Variant = null,
		p5: Variant = null,
		p6: Variant = null,
		p7: Variant = null,
		p8: Variant = null,
		p9: Variant = null,
		p10: Variant = null,
		p11: Variant = null,
		p12: Variant = null,
) -> void:
	if not DEBUG_LOG_ENABLED:
		return
	var parts: Array = [p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12]
	while not parts.is_empty() and parts[-1] == null:
		parts.resize(parts.size() - 1)
	if parts.is_empty():
		return
	if parts.size() == 1:
		print(parts[0])
	else:
		var line: PackedStringArray = []
		line.resize(parts.size())
		for i in parts.size():
			line[i] = str(parts[i])
		print(" ".join(line))

var GameHandler : GameManager
var NetworkHandler # Cannot assign, because Clent and Server using different scripts
var UnitSelectionHandler : UnitSelector
var TeamHandler : TeamSystem
var UnitSpawnHandler : UnitSpawner
var NetworkSpawner : MultiplayerSpawner
var ProjectileHandler : ProjectileSystem
var UnitTrackVisualHandler : UnitTrackVisualService
var UIHandler : GameUI
#var NavigationHandler : NavHandler # Bad approach, but signals dont work without it
var FrameGroupHandler : FrameGroup
#var GameLogHandler : GameLogs
