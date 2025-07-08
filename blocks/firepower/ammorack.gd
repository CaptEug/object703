class_name Ammorack
extends Block

var ammo_storage :float
var ammo_storage_cap:float

func deduct_ammo(amount:float) ->bool:
	if amount <= ammo_storage:
		ammo_storage -= amount
		return true
	return false
