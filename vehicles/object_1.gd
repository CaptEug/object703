extends Vehicle

func _init() -> void:
	blueprint = "Object1"

func _ready():
	super._ready()
	add_to_group("enimies")
	#open_vehicle_panel()

func _process(delta: float) -> void:
	super._process(delta)
