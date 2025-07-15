extends Node

var GameHandler : GameManager
var NetworkHandler # Cannot assign, because Clent and Server using different scripts
var UnitSelectionHandler : UnitSelector
var TeamHandler : TeamSystem
var UnitSpawnHandler : UnitSpawner
var NetworkSpawner : MultiplayerSpawner
var ProjectileHandler : ProjectileSystem
var UIHandler : GameUI
#var NavigationHandler : NavHandler # Bad approach, but signals dont work without it
#var FrameGroupHandler : FrameGroup
#var GameLogHandler : GameLogs
