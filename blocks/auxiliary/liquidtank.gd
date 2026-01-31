class_name LiquidTank
extends Block

@export var is_full:bool = false
var stored_liquid:String = ""
var stored_amount:float
var capacity:float
var accept:Array[String]

func clear_all():
	stored_liquid = ""
	stored_amount = 0.0
	is_full = false

func add_liquid(liquid:String, amount:float) -> bool:
	if not accept_liquid(liquid):
		return false
	if amount <= capacity - stored_amount:
		stored_amount += amount
		stored_liquid = liquid
		return true
	return false


func take_liquid(liquid:String, amount:float) -> bool:
	if stored_liquid != liquid:
		return false
	if amount <= stored_amount:
		stored_amount -= amount
		return false
	return false

func available_space() -> float:
	return capacity - stored_amount

func destory():
	super.destroy()
	pass

func accept_liquid(liquid:String) -> bool:
	if stored_liquid != liquid:
		if stored_liquid == "":
			return accept.has(liquid) or accept.has("ALL")
		return false
	return true
