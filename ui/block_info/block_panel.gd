class_name BlockPanel
extends FloatingPanel

const COMPACT_SIZE := Vector2(260.0, 82.0)
const CURSOR_OFFSET := Vector2(16.0, 16.0)
const EXPANDED_WIDTH := 360.0
const STORAGE_DETAIL := preload("res://ui/block_info/storage_info.tscn")
const WEAPON_DETAIL := preload("res://ui/block_info/weapon_info.tscn")
const CONTROL_DETAIL := preload("res://ui/block_info/control_info.tscn")
const DRILL_DETAIL := preload("res://ui/block_info/drill_info.tscn")
const VEHICLEBAY_DETAIL := preload("res://ui/block_info/vehiclebay_info.tscn")

var target_block: Block
var hover_block: Block
var detail_section: Node
var pinned := false

@onready var title_label: Label = $Margin/VBox/Header/Title
@onready var close_button: Button = $Margin/VBox/Header/CloseButton
@onready var status_label: Label = $Margin/VBox/Status
@onready var separator: HSeparator = $Margin/VBox/Separator
@onready var detail_scroll: ScrollContainer = $Margin/VBox/DetailScroll
@onready var detail_host: VBoxContainer = (
	$Margin/VBox/DetailScroll/DetailHost
)


func _ready() -> void:
	_set_compact_mode()
	hide()


func _physics_process(_delta: float) -> void:
	if pinned:
		if not is_instance_valid(target_block):
			close_panel()
		return
	if get_viewport().gui_get_hovered_control() != null:
		_hide_compact()
		return
	_update_hover_target()


func pin_hovered_block(
	screen_position: Vector2 = Vector2.ZERO
) -> bool:
	if pinned or not visible or not is_instance_valid(hover_block):
		return false
	var block := hover_block
	var detail_scene := _get_detail_scene(block)
	if (
		not block.has_information_panel()
		or detail_scene == null
	):
		return false

	_disconnect_target()
	target_block = block
	hover_block = null
	pinned = true
	target_block.health_changed.connect(_refresh_general)
	target_block.block_destroyed.connect(_on_target_destroyed)
	_refresh_general()
	_create_detail_section(detail_scene)
	_set_expanded_mode()
	show()
	move_to_front()
	var target_position := position
	if screen_position != Vector2.ZERO:
		target_position = screen_position + CURSOR_OFFSET
	_place_inside_viewport(target_position)
	return true


func close_panel() -> void:
	pinned = false
	hover_block = null
	hide()
	_disconnect_target()
	_set_compact_mode()


func is_pinned() -> bool:
	return pinned


func _update_hover_target() -> void:
	var current_scene := get_tree().current_scene as Node2D
	if current_scene == null:
		_hide_compact()
		return
	var world_position := current_scene.get_local_mouse_position()
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_position
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var vehicle: Vehicle
	var detected_world_block: Block
	var world_blocks: WorldBlockLayer
	var liquid_layer: LiquidLayer
	var known_world_anchor := WorldBlockLayer.INVALID_CELL
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_point(
		query
	):
		var collider: Object = hit.get("collider")
		if collider is Vehicle:
			vehicle = collider as Vehicle
		elif collider is Area2D:
			var area_block := (collider as Area2D).get_parent() as Block
			if area_block is VehicleBayBlock:
				detected_world_block = area_block
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
	elif is_instance_valid(detected_world_block):
		_show_live_block(detected_world_block)
	elif world_blocks != null:
		_show_world_block(
			world_blocks,
			world_position,
			known_world_anchor
		)
	elif liquid_layer != null:
		_show_liquid(liquid_layer, world_position)
	else:
		_hide_compact()


func _show_vehicle_block(
	vehicle: Vehicle,
	world_position: Vector2
) -> void:
	var block := vehicle.get_block(vehicle.world_to_cell(world_position))
	_show_live_block(block)


func _show_live_block(block: Block) -> void:
	if not is_instance_valid(block):
		_hide_compact()
		return
	_show_compact(
		BlockDB.get_block_name(block.block_id),
		"HP: %.1f / %.1f" % [maxf(block.hp, 0.0), block.max_hp],
		block
	)


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
		_hide_compact()
		return
	var functional_block := layer.get_functional_block_at(cell)
	if is_instance_valid(functional_block):
		_show_live_block(functional_block)
		return
	var block_id := int(state["block_id"])
	var max_hp := _get_world_block_max_hp(block_id, state)
	_show_compact(
		BlockDB.get_block_name(block_id),
		"HP: %.1f / %.1f" % [
			maxf(float(state["hp"]), 0.0),
			max_hp,
		]
	)


func _show_liquid(
	layer: LiquidLayer,
	world_position: Vector2
) -> void:
	var cell := layer.local_to_map(layer.to_local(world_position))
	var state := layer.get_celldata(cell)
	if state.is_empty():
		_hide_compact()
		return
	var total_mass := layer.get_total_liquid_mass(
		layer.get_connected_liquid(cell)
	)
	var mass_text := (
		"Total mass: %.0f kg" % total_mass
		if total_mass < 1000.0
		else "Total mass: %.1f T" % (total_mass / 1000.0)
	)
	_show_compact(
		BlockDB.get_block_name(int(state["block_id"])),
		mass_text
	)


func _show_compact(
	title: String,
	status: String,
	block: Block = null
) -> void:
	hover_block = block if is_instance_valid(block) else null
	_set_compact_mode()
	title_label.text = title
	status_label.text = status
	show()
	_place_inside_viewport(
		get_viewport().get_mouse_position() + CURSOR_OFFSET
	)


func _hide_compact() -> void:
	hover_block = null
	hide()


func _set_compact_mode() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	close_button.hide()
	separator.hide()
	detail_scroll.hide()
	size = COMPACT_SIZE


func _set_expanded_mode() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	close_button.show()
	separator.show()
	detail_scroll.show()
	var viewport_size := get_viewport_rect().size
	size = Vector2(
		minf(EXPANDED_WIDTH, viewport_size.x),
		minf(_get_detail_height(target_block), viewport_size.y)
	)


func _place_inside_viewport(target_position: Vector2) -> void:
	var viewport_size := get_viewport_rect().size
	position = target_position.clamp(
		Vector2.ZERO,
		(viewport_size - size).max(Vector2.ZERO)
	)


func _get_world_block_max_hp(
	block_id: int,
	state: Dictionary
) -> float:
	var base_size := BlockDB.get_size(block_id)
	var stored_size: Vector2i = state.get("size", base_size)
	var base_units := maxi(base_size.x * base_size.y, 1)
	var stored_units := maxi(stored_size.x * stored_size.y, 1)
	return (
		BlockDB.get_max_hp(block_id)
		* float(stored_units)
		/ float(base_units)
	)


func _disconnect_target() -> void:
	_clear_detail_section()
	if not is_instance_valid(target_block):
		target_block = null
		return
	if target_block.health_changed.is_connected(_refresh_general):
		target_block.health_changed.disconnect(_refresh_general)
	if target_block.block_destroyed.is_connected(_on_target_destroyed):
		target_block.block_destroyed.disconnect(_on_target_destroyed)
	target_block = null


func _refresh_general() -> void:
	if not is_instance_valid(target_block):
		return
	title_label.text = BlockDB.get_block_name(target_block.block_id)
	status_label.text = "HP: %.1f / %.1f" % [
		maxf(target_block.hp, 0.0),
		target_block.max_hp,
	]


func _get_detail_scene(block: Block) -> PackedScene:
	if not is_instance_valid(block):
		return null
	if block is ControlBlock:
		return CONTROL_DETAIL
	if block is Weapon:
		return WEAPON_DETAIL
	if block.get_information_panel_key() == &"drill":
		return DRILL_DETAIL
	if block.get_information_panel_key() == &"vehicle_bay":
		return VEHICLEBAY_DETAIL
	if block is ItemStorage or block is LiquidStorage:
		return STORAGE_DETAIL
	return null


func _get_detail_height(block: Block) -> float:
	if block is ControlBlock:
		return 230.0
	if block is Weapon:
		return 330.0
	if block.get_information_panel_key() == &"drill":
		return 210.0
	if block.get_information_panel_key() == &"vehicle_bay":
		return 350.0
	if block is ItemStorage or block is LiquidStorage:
		return 520.0
	return COMPACT_SIZE.y


func _create_detail_section(detail_scene: PackedScene) -> void:
	detail_section = detail_scene.instantiate()
	detail_host.add_child(detail_section)
	if detail_section.has_method("bind_block"):
		detail_section.bind_block(target_block)


func _clear_detail_section() -> void:
	if not is_instance_valid(detail_section):
		detail_section = null
		return
	if detail_section.has_method("unbind_block"):
		detail_section.unbind_block()
	detail_host.remove_child(detail_section)
	detail_section.queue_free()
	detail_section = null


func _on_target_destroyed() -> void:
	close_panel()
