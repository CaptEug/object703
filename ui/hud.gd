extends Panel

@export var UI_root : CanvasLayer
@export var gamescene : GameScene
@export var vehicle_editor : VehicleEditor
@export var settings_panel : FloatingPanel
@export var minimap : FloatingPanel

@onready var clock = $Clock

func _ready():
	pass

func _process(_delta):
	if gamescene:
		clock.text = get_clock_string(gamescene.game_time)


func get_clock_string(time) -> String:
	var cycle_duration = Globals.CYCLE_DURATION
	var total_minutes = (time / cycle_duration) * 24.0 * 60.0
	var hour = int(total_minutes / 60.0) % 24
	var minute = int(total_minutes) % 60
	return "%02d:%02d" % [hour, minute]


func _on_build_button_pressed():
	vehicle_editor.show()
	vehicle_editor.create_new_vehicle()


func _on_tank_dex_button_pressed():
	var tankdex = UI_root.find_child("TankDex", true, false) as FloatingPanel
	if tankdex:
		tankdex.visible = true
	else:
		tankdex = load("res://ui/tankdex.tscn").instantiate()
		UI_root.add_child(tankdex)


func _on_settings_button_pressed() -> void:
	settings_panel.visible = true


func _on_map_button_pressed():
	minimap.show()
