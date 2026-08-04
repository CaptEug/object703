class_name VehiclePanel
extends FloatingPanel

signal close_requested

var vehicle: Vehicle
var editing := false
var updating_name_field := false

@onready var vehicle_name_input: LineEdit = $VehicleName
@onready var vehicle_info_label: RichTextLabel = $VehicleInfo
@onready var status_label: Label = $Status


func _ready() -> void:
	vehicle_name_input.text_changed.connect(_on_vehicle_name_changed)
	set_vehicle(null)
	set_editing(false)


func _process(_delta: float) -> void:
	if vehicle != null and not is_instance_valid(vehicle):
		set_vehicle(null)
	refresh_information()


func set_vehicle(new_vehicle: Vehicle) -> void:
	vehicle = new_vehicle if is_instance_valid(new_vehicle) else null
	updating_name_field = true
	if is_instance_valid(vehicle):
		vehicle_name_input.remove_theme_color_override("font_color")
		vehicle_name_input.remove_theme_color_override("font_uneditable_color")
		vehicle_name_input.text = vehicle.vehicle_name
	else:
		var no_selection_color := Color.RED
		vehicle_name_input.add_theme_color_override("font_color", no_selection_color)
		vehicle_name_input.add_theme_color_override(
			"font_uneditable_color",
			no_selection_color
		)
		vehicle_name_input.text = "No vehicle selected"
	updating_name_field = false
	_refresh_name_field_state()
	clear_status()
	refresh_information()


func set_editing(value: bool) -> void:
	editing = value
	_refresh_name_field_state()


func _refresh_name_field_state() -> void:
	if not is_node_ready():
		return
	vehicle_name_input.editable = (
		editing and is_instance_valid(vehicle)
	)
	if not vehicle_name_input.editable:
		vehicle_name_input.release_focus()


func refresh_information() -> void:
	if not is_instance_valid(vehicle):
		vehicle_info_label.text = (
			"Weight: --\n"
			+ "Speed: --\n"
			+ "[color=#ff493d]Control: No vehicle selected[/color]"
		)
		return
	var control_text := "[color=#ff493d]No control block[/color]"
	if is_instance_valid(vehicle.active_control_block):
		control_text = BlockDB.get_block_name(
			vehicle.active_control_block.block_id
		)
	vehicle_info_label.text = (
		"Weight: %.1f t\n" % vehicle.total_mass
		+ "Speed: %.1f tiles/s\n" % (
			vehicle.linear_velocity.length() / Globals.TILE_SIZE
		)
		+ "Control: %s" % control_text
	)


func show_status(message: String) -> void:
	status_label.text = message
	status_label.tooltip_text = message


func clear_status() -> void:
	status_label.text = ""
	status_label.tooltip_text = ""


func _on_vehicle_name_changed(new_name: String) -> void:
	if (
		updating_name_field
		or not editing
		or not is_instance_valid(vehicle)
	):
		return
	vehicle.vehicle_name = new_name


func _on_close_button_pressed() -> void:
	close_requested.emit()
