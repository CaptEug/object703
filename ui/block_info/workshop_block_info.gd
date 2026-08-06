class_name MaintenanceBayBlockInfo
extends VBoxContainer

const ACTION_ICON_ATLAS := preload("res://assets/icons/icons.png")
const ACTION_EDIT_REGION := Rect2(0, 160, 32, 32)
const ACTION_CREATE_REGION := Rect2(32, 160, 32, 32)

var workshop: MaintenanceBayBlock
var docked_vehicle: Vehicle
var _updating_direction := false
var _editor_status := ""
var _action_region := Rect2()

@onready var docking_label: Label = $Docking
@onready var direction_select: OptionButton = $DirectionRow/Direction
@onready var vehicle_action_button: TextureButton = $VehicleActionButton
@onready var status_label: Label = $Status


func _ready() -> void:
	set_process(false)


func bind_block(block: Block) -> void:
	workshop = block as MaintenanceBayBlock
	if not is_instance_valid(workshop):
		return
	if not workshop.docked_vehicle_changed.is_connected(
		_on_docked_vehicle_changed
	):
		workshop.docked_vehicle_changed.connect(
			_on_docked_vehicle_changed
		)
	if not workshop.front_direction_changed.is_connected(
		_on_front_direction_changed
	):
		workshop.front_direction_changed.connect(
			_on_front_direction_changed
		)
	var editor := _get_vehicle_editor()
	if (
		editor != null
		and not editor.workshop_session_changed.is_connected(
			_on_workshop_session_changed
		)
	):
		editor.workshop_session_changed.connect(
			_on_workshop_session_changed
		)
	if (
		editor != null
		and not editor.status_changed.is_connected(
			_on_editor_status_changed
		)
	):
		editor.status_changed.connect(_on_editor_status_changed)
	if editor != null:
		editor.set_workshop_context(workshop, docked_vehicle)
	_refresh_all()
	set_process(true)


func unbind_block() -> void:
	set_process(false)
	if is_instance_valid(workshop):
		if workshop.docked_vehicle_changed.is_connected(
			_on_docked_vehicle_changed
		):
			workshop.docked_vehicle_changed.disconnect(
				_on_docked_vehicle_changed
			)
		if workshop.front_direction_changed.is_connected(
			_on_front_direction_changed
		):
			workshop.front_direction_changed.disconnect(
				_on_front_direction_changed
			)
	var editor := _get_vehicle_editor()
	if (
		editor != null
		and editor.workshop_session_changed.is_connected(
			_on_workshop_session_changed
		)
	):
		editor.workshop_session_changed.disconnect(
			_on_workshop_session_changed
		)
	if (
		editor != null
		and editor.status_changed.is_connected(
			_on_editor_status_changed
		)
	):
		editor.status_changed.disconnect(_on_editor_status_changed)
	if editor != null:
		editor.clear_workshop_context(workshop)
	workshop = null
	docked_vehicle = null


func _process(_delta: float) -> void:
	if not is_instance_valid(workshop):
		return
	_refresh_docked_vehicle()
	_refresh_action_state()


func _refresh_all() -> void:
	if not is_instance_valid(workshop):
		return
	_updating_direction = true
	direction_select.select(int(workshop.vehicle_front))
	_updating_direction = false
	_refresh_docked_vehicle()
	_refresh_action_state()


func _refresh_docked_vehicle() -> void:
	docked_vehicle = workshop.get_docked_vehicle()
	docking_label.text = "Docked vehicle: %s" % (
		docked_vehicle.vehicle_name
		if is_instance_valid(docked_vehicle)
		else "None"
	)
	var editor := _get_vehicle_editor()
	if editor != null:
		editor.set_workshop_context(workshop, docked_vehicle)


func _refresh_action_state() -> void:
	var editor := _get_vehicle_editor()
	var owns_session := (
		editor != null and editor.active_workshop == workshop
	)
	direction_select.disabled = owns_session
	if owns_session:
		vehicle_action_button.hide()
		status_label.text = (
			_editor_status
			if not _editor_status.is_empty()
			else "Editing %s" % (
				editor.vehicle.vehicle_name
				if is_instance_valid(editor.vehicle)
				else "new vehicle"
			)
		)
		return
	vehicle_action_button.show()
	if not is_instance_valid(docked_vehicle):
		_set_action_icon(ACTION_CREATE_REGION, "Create vehicle")
		var building := _get_building()
		vehicle_action_button.disabled = building == null
		status_label.text = (
			"Vehicle workshop is unavailable"
			if building == null
			else ""
		)
		return
	_set_action_icon(ACTION_EDIT_REGION, "Edit docked vehicle")
	var reason := _get_docked_vehicle_rejection()
	vehicle_action_button.disabled = not reason.is_empty()
	status_label.text = reason


func _get_docked_vehicle_rejection() -> String:
	if not is_instance_valid(docked_vehicle):
		return "No vehicle is docked"
	var building := _get_building()
	if building == null:
		return "Vehicle workshop is unavailable"
	if docked_vehicle.owner_id != building.owner_id:
		return "Vehicle owner does not match vehicle workshop owner"
	if docked_vehicle.linear_velocity.length() > 2.0:
		return "Vehicle must stop before editing"
	if absf(docked_vehicle.angular_velocity) > 0.05:
		return "Vehicle must stop rotating before editing"
	if not workshop.is_vehicle_fully_inside(docked_vehicle):
		return "Vehicle is not fully inside this maintenance bay"
	return ""


func _set_action_icon(region: Rect2, tooltip: String) -> void:
	if _action_region != region:
		_action_region = region
		var texture := AtlasTexture.new()
		texture.atlas = ACTION_ICON_ATLAS
		texture.region = region
		vehicle_action_button.texture_normal = texture
	vehicle_action_button.tooltip_text = tooltip


func _get_building() -> Building:
	var world_layer := workshop.block_host as WorldBlockLayer
	return (
		world_layer.get_building_at(workshop.origin_cell)
		if world_layer != null
		else null
	)


func _get_vehicle_editor() -> VehicleEditor:
	return get_tree().get_first_node_in_group("vehicle_editor") as VehicleEditor


func _on_direction_selected(index: int) -> void:
	if _updating_direction or not is_instance_valid(workshop):
		return
	workshop.set_vehicle_front(index)
	var editor := _get_vehicle_editor()
	if editor != null and editor.active_workshop == workshop:
		editor.refresh_workshop_camera()


func _on_vehicle_action_pressed() -> void:
	var editor := _get_vehicle_editor()
	if editor == null:
		status_label.text = "Vehicle editor is unavailable"
		return
	if editor.active_workshop == workshop:
		return
	var result := (
		editor.begin_workshop_edit(workshop, docked_vehicle)
		if is_instance_valid(docked_vehicle)
		else editor.begin_new_workshop_vehicle(workshop)
	)
	status_label.text = str(result.get("message", ""))


func _on_docked_vehicle_changed(_vehicle: Vehicle) -> void:
	_refresh_docked_vehicle()
	_refresh_action_state()


func _on_front_direction_changed(_direction: int) -> void:
	_refresh_all()


func _on_workshop_session_changed(_active: bool) -> void:
	_editor_status = ""
	_refresh_all()


func _on_editor_status_changed(message: String) -> void:
	var editor := _get_vehicle_editor()
	if editor == null:
		return
	if editor.active_workshop == workshop or editor.workshop_context == workshop:
		_editor_status = message
		status_label.text = message
