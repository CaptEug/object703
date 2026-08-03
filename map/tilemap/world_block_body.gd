class_name WorldBlockBody
extends StaticBody2D

var world_block_layer: WorldBlockLayer
var anchor_cell := Vector2i.ZERO


func configure(
	layer: WorldBlockLayer,
	block_anchor: Vector2i
) -> void:
	world_block_layer = layer
	anchor_cell = block_anchor


func damage(
	amount: float,
	damage_type: StringName
) -> Dictionary:
	if world_block_layer == null:
		return BlockDamage.miss()
	return world_block_layer.damage_block_at(
		anchor_cell,
		amount,
		damage_type
	)


func _input_event(
	viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if (
		world_block_layer == null
		or not event is InputEventMouseButton
		or not event.pressed
	):
		return
	var handled := false
	if event.button_index == MOUSE_BUTTON_RIGHT:
		handled = world_block_layer.open_information_panel_at(
			anchor_cell,
			viewport.get_mouse_position()
		)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		handled = world_block_layer.open_building_panel_at(anchor_cell)
	if handled:
		viewport.set_input_as_handled()
