extends Panel

@onready var textlabel: RichTextLabel = $RichTextLabel
@export var padding: Vector2 = Vector2(16, 32)


func _ready() -> void:
	visible = false


func _physics_process(_delta: float) -> void:
	if get_viewport().gui_get_hovered_control():
		visible = false
		return
	var world_position: Vector2 = (
		get_tree().current_scene.get_local_mouse_position()
	)
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_position
	query.collide_with_areas = true
	query.collide_with_bodies = true
	global_position = (
		get_viewport().get_mouse_position() + Vector2(16, 16)
	)

	var vehicle: Vehicle
	var world_blocks: WorldBlockLayer
	var liquid_layer: LiquidLayer
	var known_world_anchor := WorldBlockLayer.INVALID_CELL
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_point(
		query
	):
		var collider: Object = hit.get("collider")
		if collider is Vehicle:
			vehicle = collider as Vehicle
		elif collider is WorldBlockBody:
			var body := collider as WorldBlockBody
			world_blocks = body.world_block_layer
			known_world_anchor = body.anchor_cell
		elif collider is WorldBlockLayer:
			world_blocks = collider as WorldBlockLayer
		elif collider is LiquidLayer:
			liquid_layer = collider as LiquidLayer

	if vehicle != null:
		_show_vehicle_block(vehicle, world_position)
	elif world_blocks != null:
		_show_world_block(
			world_blocks,
			world_position,
			known_world_anchor
		)
	elif liquid_layer != null:
		_show_liquid(liquid_layer, world_position)
	else:
		visible = false
	call_deferred("update_panel_size")


func _show_vehicle_block(
	vehicle: Vehicle,
	world_position: Vector2
) -> void:
	var block := vehicle.get_block(vehicle.world_to_cell(world_position))
	if block == null:
		visible = false
		return
	visible = true
	textlabel.text = "%s\nHP: %.1f" % [
		BlockDB.get_block_name(block.block_id),
		block.hp,
	]
	if block is LiquidStorage:
		textlabel.text += "\n%.2f mass %s stored" % [
			block.stored,
			block.liquid,
		]


func _show_world_block(
	layer: WorldBlockLayer,
	world_position: Vector2,
	known_anchor: Vector2i
) -> void:
	var cell := known_anchor
	if cell == WorldBlockLayer.INVALID_CELL:
		cell = layer.local_to_map(layer.to_local(world_position))
	var state := layer.get_block_state(cell)
	if state.is_empty():
		visible = false
		return
	var block_id := int(state["block_id"])
	visible = true
	textlabel.text = "%s\nHP: %.1f" % [
		BlockDB.get_block_name(block_id),
		float(state["hp"]),
	]


func _show_liquid(
	layer: LiquidLayer,
	world_position: Vector2
) -> void:
	var cell := layer.local_to_map(layer.to_local(world_position))
	var state := layer.get_celldata(cell)
	if state.is_empty():
		visible = false
		return
	var block_id := int(state["block_id"])
	var connected := layer.get_connected_liquid(cell)
	var total_mass := layer.get_total_liquid_mass(connected)
	visible = true
	textlabel.text = BlockDB.get_block_name(block_id)
	if total_mass < 1000.0:
		textlabel.text += "\nTotal mass: %.0f kg" % total_mass
	else:
		textlabel.text += "\nTotal mass: %.1f T" % (
			total_mass / 1000.0
		)


func update_panel_size() -> void:
	size = textlabel.get_size() + padding
