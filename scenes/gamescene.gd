extends Node2D

@onready var gamemap:GameMap = $Gamemap
@onready var gameUI:CanvasLayer = $UI
@onready var camera:Camera2D = $Camera2D

# In-Game Time Management
var game_time:= 200.0
var cycle_duration := 600.0


func _ready() -> void:
	GameState.current_gamescene = self

func _process(delta: float) -> void:
	update_game_time(delta)

func update_game_time(delta):
	game_time = fmod(game_time + delta, cycle_duration)
	gamemap.canvas_modulate.time = game_time
