extends Block

const HITPOINT:float = 2000
const WEIGHT:float = 10000
const BLOCK_NAME:String = 'smelter'
const TYPE:= "Industrial"
const SIZE:= Vector2(4, 4)
const COST:= {"metal": 1}

var description := ""
#var outline_tex := preload("res://assets/outlines/pike_outline.png")

var on:bool

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

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton:
		on = event.pressed


func update_core_light(delta):
	var core_alpha = $Sprite2D/MoltenCore.modulate.a
	if on:
		core_alpha = clamp(core_alpha + 0.5 * delta, 0.0, 1.0)
	else:
		core_alpha = clamp(core_alpha - 0.5 * delta, 0.0, 1.0)
	$Sprite2D/MoltenCore.modulate.a = core_alpha
