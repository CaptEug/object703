extends Block

const HITPOINT:int = 100
const WEIGHT: float = 2.0
var size:= Vector2(1, 1)

func get_weight() -> float:
	return WEIGHT
# Called when the node enters the scene tree for the first time.
func _ready():
	super._ready()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
