extends Block

const HITPOINT:int = 100
const WEIGHT:int = 2
<<<<<<< HEAD
var power:int = 200
=======
var size:= Vector2(1, 1)
var power:int = 20
>>>>>>> 5f0892fff55e88c4300a88814ca203bfc9ea8839

func get_weight() -> float:
	return WEIGHT
# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("engines")
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
