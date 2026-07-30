class_name VehiclePanel
extends Panel

signal edit_requested
signal finish_requested
signal close_requested

var vehicle: Vehicle
var editing := false
var updating_name_field := false

@onready var vehicle_name_input: LineEdit = $VehicleName
@onready var vehicle_info_label: RichTextLabel = $VehicleInfo
@onready var status_label: Label = $Status
@onready var edit_button: Button = $EditButton


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
		vehicle_name_input.editable = true
		vehicle_name_input.remove_theme_color_override("font_color")
		vehicle_name_input.remove_theme_color_override("font_uneditable_color")
		vehicle_name_input.text = vehicle.vehicle_name
	else:
		vehicle_name_input.editable = false
		var no_selection_color := Color.RED
		vehicle_name_input.add_theme_color_override("font_color", no_selection_color)
		vehicle_name_input.add_theme_color_override(
			"font_uneditable_color",
			no_selection_color
		)
		vehicle_name_input.text = "No vehicle selected"
	updating_name_field = false
	edit_button.disabled = not is_instance_valid(vehicle)
	clear_status()
	refresh_information()


func set_editing(value: bool) -> void:
	editing = value
	edit_button.text = "Finish Editing" if editing else "Edit Vehicle"


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
	if updating_name_field or not is_instance_valid(vehicle):
		return
	vehicle.vehicle_name = new_name


func _on_edit_button_pressed() -> void:
	if editing:
		finish_requested.emit()
	elif is_instance_valid(vehicle):
		edit_requested.emit()


func _on_close_button_pressed() -> void:
	close_requested.emit()
