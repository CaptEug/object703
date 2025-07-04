extends Panel

@onready var fuel_progressbar = $RichTextLabel/Fuel
@onready var ammo_progressbar = $RichTextLabel/Ammo
var selected_vehicle:Vehicle


# Called when the node enters the scene tree for the first time.
func _ready():
	if selected_vehicle:
		$RichTextLabel.text = selected_vehicle.vehicle_name
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	fuel_progressbar.value = 77
	if selected_vehicle:
		retrieve_vehicle_data()
		draw_grid()

func retrieve_vehicle_data():
	fuel_progressbar.max_value = selected_vehicle.total_fuel_cap
	fuel_progressbar.value = selected_vehicle.total_fuel
	ammo_progressbar.max_value = selected_vehicle.total_ammo_cap
	ammo_progressbar.value = selected_vehicle.total_ammo

func draw_grid():
	var grid = selected_vehicle.grid
	
