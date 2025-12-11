extends Fueltank

const HITPOINT:float = 400
const WEIGHT:float = 200
const BLOCK_NAME:String = 'fuel tank'
const TYPE:= "Mobility"
const SIZE:= Vector2(1, 1)
const INITIAL_GAS: int = 10

var description := "存储燃料供发动机使用"

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	type = TYPE
	size = SIZE

func _ready():
	super._ready()
	clear_all()
	add_item("gas", INITIAL_GAS)
