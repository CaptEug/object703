class_name ControlBlockInfoSection
extends VBoxContainer

var control_block: ControlBlock

@onready var status_label: Label = $Status
@onready var active_toggle: CheckButton = $ActiveToggle


func _process(_delta: float) -> void:
	_refresh()


func bind_block(block: Block) -> void:
	unbind_block()
	if not block is ControlBlock:
		return
	control_block = block as ControlBlock
	_refresh()


func unbind_block() -> void:
	control_block = null


func _refresh() -> void:
	if not is_instance_valid(control_block):
		status_label.text = "Control unavailable"
		active_toggle.disabled = true
		active_toggle.set_pressed_no_signal(false)
		return
	var target_vehicle := control_block.vehicle
	var available := (
		is_instance_valid(target_vehicle)
		and target_vehicle.control_blocks.has(control_block)
	)
	var is_active := (
		available
		and target_vehicle.active_control_block == control_block
	)
	active_toggle.disabled = not available
	active_toggle.set_pressed_no_signal(is_active)
	status_label.text = (
		"Current functioning control"
		if is_active
		else "Inactive control"
	)


func _on_active_toggle_toggled(enabled: bool) -> void:
	if not is_instance_valid(control_block):
		return
	var target_vehicle := control_block.vehicle
	if not is_instance_valid(target_vehicle):
		return
	if enabled:
		target_vehicle.set_active_control_block(control_block)
	_refresh()
