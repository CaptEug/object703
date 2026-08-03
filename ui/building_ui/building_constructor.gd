class_name BuildingConstructor
extends Control

signal active_changed(enabled: bool)

enum EditMode {
	BUILD,
	DISMANTLE,
}

enum PlacementState {
	BLOCKED,
	MISSING_MATERIALS,
	READY,
}

const PREVIEW_READY := Color(0.25, 1.0, 0.35, 0.65)
const PREVIEW_MISSING := Color(1.0, 0.72, 0.12, 0.65)
const PREVIEW_BLOCKED := Color(1.0, 0.18, 0.18, 0.65)
const CELL_HALF_SIZE := Globals.TILE_SIZE * 0.5 - 0.1

@export var gamemap: GameMap
@export var owner_id: StringName = &"player"
@export_range(1.0, 64.0, 1.0) var construction_range_tiles := 8.0
@export var saw_cursor: Texture2D

var active := false
var edit_mode := EditMode.BUILD
var selected_block: Block
var preview_block: Block
var preview_cell := WorldBlockLayer.INVALID_CELL
var preview_rotation := 0

@onready var constructor_dock: Panel = $ConstructorDock
@onready var palette: BlockPalette = (
	$ConstructorDock/PaletteArea/Panel/Clipper/BlockPalette
)
@onready var dismantle_button: TextureButton = (
	$ConstructorDock/Tools/DismantleButton
)
@onready var status_label: Label = $ConstructorDock/Status

var world_blocks: WorldBlockLayer:
	get:
		return gamemap.world_blocks if is_instance_valid(gamemap) else null


func _ready() -> void:
	add_to_group("building_constructor")
	constructor_dock.hide()
	set_process(false)
	set_process_unhandled_input(false)


func _exit_tree() -> void:
	if active:
		Input.set_custom_mouse_cursor(null)


func is_active() -> bool:
	return active


func toggle_constructor() -> void:
	set_active(not active)


func set_active(enabled: bool) -> void:
	if active == enabled:
		return
	if enabled and world_blocks == null:
		return
	active = enabled
	constructor_dock.visible = active
	set_process(active)
	set_process_unhandled_input(active)
	if active:
		status_label.text = "Select a block to construct"
		set_mode(EditMode.BUILD)
	else:
		palette.selected_block = null
		selected_block = null
		clear_preview_block()
		status_label.text = ""
		Input.set_custom_mouse_cursor(null)
	active_changed.emit(active)


func _process(_delta: float) -> void:
	if not active:
		return
	selected_block = palette.selected_block
	if edit_mode == EditMode.BUILD:
		update_preview()
	else:
		clear_preview_block()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("ui_cancel"):
		set_active(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ROTATE"):
		if (
			selected_block != null
			and BlockDB.is_rotatable(selected_block.block_id)
		):
			preview_rotation = wrapi(preview_rotation + 1, 0, 4)
		else:
			preview_rotation = 0
		get_viewport().set_input_as_handled()
		return
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_X
	):
		toggle_mode()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if edit_mode == EditMode.BUILD:
			palette.selected_block = null
			selected_block = null
			clear_preview_block()
		else:
			set_mode(EditMode.BUILD)
		get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if edit_mode == EditMode.BUILD:
		place_selected_block()
	else:
		remove_block_at_mouse()
	get_viewport().set_input_as_handled()


func toggle_mode() -> void:
	if edit_mode == EditMode.BUILD:
		set_mode(EditMode.DISMANTLE)
	else:
		set_mode(EditMode.BUILD)


func set_mode(new_mode: EditMode) -> void:
	edit_mode = new_mode
	dismantle_button.button_pressed = edit_mode == EditMode.DISMANTLE
	clear_preview_block()
	preview_rotation = 0
	if not active:
		Input.set_custom_mouse_cursor(null)
	elif edit_mode == EditMode.DISMANTLE and saw_cursor != null:
		Input.set_custom_mouse_cursor(
			saw_cursor,
			Input.CURSOR_ARROW,
			Vector2(8, 8)
		)
		status_label.text = "Dismantle: select a friendly building block"
	else:
		Input.set_custom_mouse_cursor(null)
		status_label.text = "Select a block to construct"


func update_preview() -> void:
	preview_cell = _get_mouse_world_cell()
	if (
		selected_block == null
		or preview_cell == WorldBlockLayer.INVALID_CELL
	):
		clear_preview_block()
		return
	if (
		preview_block == null
		or preview_block.block_id != selected_block.block_id
	):
		create_preview_block()
	if preview_block == null:
		return
	preview_block.update_world_transform(
		world_blocks,
		preview_cell,
		preview_rotation
	)
	preview_block.refresh_shared_visual()
	var report := _get_placement_report(
		selected_block.block_id,
		preview_cell,
		preview_rotation
	)
	match int(report["state"]):
		PlacementState.READY:
			preview_block.modulate = PREVIEW_READY
		PlacementState.MISSING_MATERIALS:
			preview_block.modulate = PREVIEW_MISSING
		_:
			preview_block.modulate = PREVIEW_BLOCKED


func create_preview_block() -> void:
	clear_preview_block()
	if selected_block == null or world_blocks == null:
		return
	var scene := BlockDB.get_scene(selected_block.block_id)
	if scene == null:
		return
	preview_block = scene.instantiate() as Block
	if preview_block == null:
		return
	preview_block.block_id = selected_block.block_id
	preview_block.z_index = 100
	world_blocks.add_child(preview_block)
	preview_block.process_mode = Node.PROCESS_MODE_DISABLED
	_disable_preview_features(preview_block)


func clear_preview_block() -> void:
	if is_instance_valid(preview_block):
		preview_block.queue_free()
	preview_block = null


func place_selected_block() -> void:
	if selected_block == null or world_blocks == null:
		return
	preview_cell = _get_mouse_world_cell()
	if preview_cell == WorldBlockLayer.INVALID_CELL:
		return
	var result := construct_block_at(
		selected_block.block_id,
		preview_cell,
		preview_rotation
	)
	status_label.text = str(result.get("message", ""))


func construct_block_at(
	block_id: int,
	cell: Vector2i,
	rotation_index: int = 0
) -> Dictionary:
	var report := _get_placement_report(
		block_id,
		cell,
		rotation_index
	)
	match int(report["state"]):
		PlacementState.BLOCKED:
			return {
				"ok": false,
				"message": str(
					report.get("message", "Cannot construct here")
				),
			}
		PlacementState.MISSING_MATERIALS:
			return {
				"ok": false,
				"message": "Missing: %s"
				% ConstructionSupport.format_cost(report["missing"])
			}

	var cost: Dictionary = report["cost"]
	var storages: Array[ItemStorage] = report["storages"]
	var payment := ConstructionSupport.consume(cost, storages)
	if not payment["ok"]:
		return {
			"ok": false,
			"message": "Missing: %s"
			% ConstructionSupport.format_cost(payment["missing"])
		}
	if not world_blocks.place_block(
		block_id,
		cell,
		rotation_index,
		-1.0,
		owner_id
	):
		ConstructionSupport.refund(payment["withdrawals"])
		return {
			"ok": false,
			"message": "Cannot construct here; materials returned",
		}
	_refresh_minimap_for_block(block_id, cell, rotation_index)
	return {
		"ok": true,
		"message": "Constructed %s" % BlockDB.get_block_name(block_id),
	}


func remove_block_at_mouse() -> void:
	if world_blocks == null:
		return
	var result := dismantle_block_at(_get_mouse_world_cell())
	status_label.text = str(result.get("message", ""))


func dismantle_block_at(cell: Vector2i) -> Dictionary:
	var anchor := world_blocks.get_block_anchor(cell)
	if anchor == WorldBlockLayer.INVALID_CELL:
		return {"ok": false, "message": "No building block here"}
	var block_id := world_blocks.get_block_id_at(anchor)
	if not BlockDB.is_constructed(block_id):
		return {
			"ok": false,
			"message": "Natural blocks cannot be dismantled",
		}
	var building := world_blocks.get_building_at(anchor)
	if building == null or building.owner_id != owner_id:
		return {
			"ok": false,
			"message": "Cannot dismantle another owner's building",
		}
	if world_blocks.destroy_block_at(anchor, false):
		return {
			"ok": true,
			"message": "Dismantled %s" % BlockDB.get_block_name(block_id),
		}
	return {"ok": false, "message": "Could not dismantle block"}


func _get_placement_report(
	block_id: int,
	anchor: Vector2i,
	rotation_index: int
) -> Dictionary:
	var empty_storages: Array[ItemStorage] = []
	var result := {
		"state": PlacementState.BLOCKED,
		"cost": {},
		"storages": empty_storages,
		"missing": {},
		"message": "Cannot construct here",
	}
	if (
		world_blocks == null
		or not BlockDB.is_constructed(block_id)
		or not BlockDB.can_place_on(block_id, BlockDB.HOST_WORLD)
		or not world_blocks.can_place_block(
			block_id,
			anchor,
			rotation_index,
			owner_id
		)
		or _footprint_overlaps_vehicle(
			block_id,
			anchor,
			rotation_index
		)
	):
		return result

	var cost := BlockDB.get_construction_cost(block_id)
	var build_position := _get_block_center_world(
		block_id,
		anchor,
		rotation_index
	)
	var construction_range := (
		construction_range_tiles * Globals.TILE_SIZE
	)
	if not ConstructionSupport.has_world_construction_support(
		get_tree(),
		build_position,
		construction_range,
		owner_id
	):
		result["message"] = "No friendly construction support in range"
		return result
	var storages: Array[ItemStorage] = []
	if not cost.is_empty():
		storages = ConstructionSupport.get_world_candidate_storages(
			get_tree(),
			build_position,
			construction_range,
			owner_id
		)
	var missing := ConstructionSupport.get_missing(cost, storages)
	result["cost"] = cost
	result["storages"] = storages
	result["missing"] = missing
	result["state"] = (
		PlacementState.READY
		if missing.is_empty()
		else PlacementState.MISSING_MATERIALS
	)
	return result


func _get_mouse_world_cell() -> Vector2i:
	var camera := get_viewport().get_camera_2d()
	if camera == null or world_blocks == null:
		return WorldBlockLayer.INVALID_CELL
	return world_blocks.local_to_map(
		world_blocks.to_local(camera.get_global_mouse_position())
	)


func _get_block_center_world(
	block_id: int,
	anchor: Vector2i,
	rotation_index: int
) -> Vector2:
	var block_size := BlockDB.get_size(block_id)
	if BlockDB.normalize_rotation(block_id, rotation_index) % 2 != 0:
		block_size = Vector2i(block_size.y, block_size.x)
	var local_center := (
		(Vector2(anchor) + Vector2(block_size) * 0.5)
		* Globals.TILE_SIZE
	)
	return world_blocks.to_global(local_center)


func _get_occupied_cells(
	block_id: int,
	anchor: Vector2i,
	rotation_index: int
) -> Array[Vector2i]:
	var block_size := BlockDB.get_size(block_id)
	if BlockDB.normalize_rotation(block_id, rotation_index) % 2 != 0:
		block_size = Vector2i(block_size.y, block_size.x)
	var result: Array[Vector2i] = []
	for y in range(block_size.y):
		for x in range(block_size.x):
			result.append(anchor + Vector2i(x, y))
	return result


func _footprint_overlaps_vehicle(
	block_id: int,
	anchor: Vector2i,
	rotation_index: int
) -> bool:
	var construction_cells := _get_occupied_cells(
		block_id,
		anchor,
		rotation_index
	)
	for node: Node in get_tree().get_nodes_in_group("vehicles"):
		var target_vehicle := node as Vehicle
		if not is_instance_valid(target_vehicle):
			continue
		for target_block: Block in target_vehicle.blocks:
			for vehicle_cell: Vector2i in target_block.get_occupied_cells():
				var vehicle_polygon := _make_cell_polygon(
					target_vehicle,
					(Vector2(vehicle_cell) + Vector2(0.5, 0.5))
					* Globals.TILE_SIZE
				)
				for construction_cell: Vector2i in construction_cells:
					var world_polygon := _make_cell_polygon(
						world_blocks,
						world_blocks.map_to_local(construction_cell)
					)
					if not Geometry2D.intersect_polygons(
						world_polygon,
						vehicle_polygon
					).is_empty():
						return true
	return false


func _make_cell_polygon(
	host: Node2D,
	local_center: Vector2
) -> PackedVector2Array:
	var half := CELL_HALF_SIZE
	return PackedVector2Array([
		host.to_global(local_center + Vector2(-half, -half)),
		host.to_global(local_center + Vector2(half, -half)),
		host.to_global(local_center + Vector2(half, half)),
		host.to_global(local_center + Vector2(-half, half)),
	])


func _disable_preview_features(node: Node) -> void:
	if node is CollisionShape2D:
		(node as CollisionShape2D).disabled = true
	elif node is CollisionPolygon2D:
		(node as CollisionPolygon2D).disabled = true
	elif node is Area2D:
		var area := node as Area2D
		area.monitoring = false
		area.monitorable = false
	for child: Node in node.get_children():
		_disable_preview_features(child)


func _refresh_minimap_for_block(
	block_id: int,
	anchor: Vector2i,
	rotation_index: int
) -> void:
	if is_instance_valid(gamemap.minimap):
		gamemap.minimap.update_cellmap(
			_get_occupied_cells(block_id, anchor, rotation_index)
		)


func _on_dismantle_button_pressed() -> void:
	toggle_mode()
