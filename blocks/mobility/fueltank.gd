class_name Fueltank
extends Block

var fuel_storage:float

func use_fuel(power, delta):
	if fuel_storage > 0:
		fuel_storage = fuel_storage - power * delta
		if fuel_storage < 0 :
			fuel_storage = 0
