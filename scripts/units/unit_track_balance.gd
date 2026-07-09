class_name UnitTrackBalance
extends RefCounted

## Хелперы стоимости для масштабирования следов. Визуальные параметры — в @export ноды UnitTracks.

static func resolve_cost(unit: BaseUnit) -> int:
	if unit.preset_cost > 0:
		return unit.preset_cost
	return UnitPresetBalance.calculate_cost(
		UnitPresetBalance.default_stats(), unit.is_command_unit()
	)
