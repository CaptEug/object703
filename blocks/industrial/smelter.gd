extends Manufactory

const HITPOINT:float = 2000
const WEIGHT:float = 10000
const BLOCK_NAME:String = 'smelter'
const TYPE:= "Industrial"
const SIZE:= Vector2(4, 4)
const COST:= {"metal": 1}
const RECIPES:= [
	{
		"inputs": {"hematite": 1, "coal": 1},
		"outputs": {"metal": 1},
		"production_time": 5
		},
	{
		"inputs": {"malachite": 1, "coal": 1},
		"outputs": {"metal": 1},
		"production_time": 5
		},
]

var description := ""
#var outline_tex := preload("res://assets/outlines/pike_outline.png")

@onready var canvas_mod = get_tree().current_scene.find_child("CanvasModulate") as CanvasModulate

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	cost = COST

func _process(delta):
	super._process(delta)
	update_core_light(delta)


func update_core_light(delta):
	var core_alpha = $Sprite2D/MoltenCore.modulate.a
	if working:
		core_alpha = clamp(core_alpha + 0.5 * delta, 0.0, 1.0)
	else:
		core_alpha = clamp(core_alpha - 0.5 * delta, 0.0, 1.0)
	var c = canvas_mod.color
	# Compute per-channel inverse, avoid divide by zero
	$Sprite2D/MoltenCore.modulate = Color(1.2 / max(c.r, 0.001), 1.2 / max(c.g, 0.001), 1.2 / max(c.b, 0.001), core_alpha)
