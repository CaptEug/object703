class_name LiquidStorage
extends Block

@export var liquid_port: Vector2i = Vector2i.ZERO
@export var accept: Array[String] = ["petroleum", "water"]

@export var capacity: float = 100.0
@export var stored: float = 0.0
@export var liquid : String = ""


func has_liquid(liquid_type: String, amount: float) -> bool:
	return liquid == liquid_type and stored >= amount


func take_liquid(liquid_type: String, amount: float) -> float:
	if stored == 0:
		return 0.0
	if liquid != liquid_type:
		return 0.0
	
	var taken := minf(stored, amount)
	stored -= taken
	
	# clear type if empty
	if stored == 0:
		liquid = ""
	
	return taken


func add_liquid(liquid_type: String, amount: float) -> float:
	if not accept.has(liquid_type):
		return 0.0
	# if empty, adopt type
	if stored == 0:
		liquid = liquid_type
	# prevent mixing
	if liquid != liquid_type:
		return 0.0
	
	var space := capacity - stored
	if space == 0:
		return 0.0
	
	var accepted := minf(space, amount)
	stored += accepted
	
	return accepted
