extends Vehicle

func _init() -> void:
	blueprint = "Object1"

func _process(delta: float) -> void:
	super._process(delta)
	print(vehicle_size)
	
