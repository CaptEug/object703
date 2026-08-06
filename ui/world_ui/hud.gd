extends Panel

@export var UI_root : CanvasLayer
@export var gamescene : GameScene
@export var vehicle_editor : VehicleEditor
@export var vehicle_panel: VehiclePanel
@export var building_constructor: BuildingConstructor
@export var settings_panel : FloatingPanel
@export var minimap : FloatingPanel

@onready var clock = $Clock
@onready var build_button: TextureButton = $BuildButton

func _ready() -> void:
	if building_constructor != null:
		building_constructor.active_changed.connect(
			_on_building_constructor_active_changed
		)


func _unhandled_input(event: InputEvent) -> void:
	if (
		not event.is_action_pressed("TOGGLE_EDITOR")
		or (event is InputEventKey and event.echo)
	):
		return
	if building_constructor != null and building_constructor.is_active():
		building_constructor.set_active(false)
	elif (
		vehicle_editor != null
		and vehicle_editor.try_toggle_workshop_context()
	):
		pass
	elif building_constructor != null:
		building_constructor.set_active(true)
	get_viewport().set_input_as_handled()

func _process(_delta):
	if gamescene:
		clock.text = get_clock_string(gamescene.game_time)


func get_clock_string(time) -> String:
	var cycle_duration = Globals.CYCLE_DURATION
	var total_minutes = (time / cycle_duration) * 24.0 * 60.0
	var hour = int(total_minutes / 60.0) % 24
	var minute = int(total_minutes) % 60
	return "%02d:%02d" % [hour, minute]


func _on_build_button_toggled(enabled: bool) -> void:
	if building_constructor == null:
		build_button.set_pressed_no_signal(false)
		return
	if enabled and vehicle_editor != null:
		vehicle_editor.close_editor()
	if enabled and vehicle_panel != null:
		vehicle_panel.close_panel()
	building_constructor.set_active(enabled)
	build_button.set_pressed_no_signal(building_constructor.is_active())


func _on_building_constructor_active_changed(enabled: bool) -> void:
	build_button.set_pressed_no_signal(enabled)


func _on_settings_button_pressed() -> void:
	settings_panel.visible = true


func _on_map_button_pressed():
	minimap.show()
