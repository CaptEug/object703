class_name BlockInformationPanel
extends FloatingPanel

const STORAGE_DETAIL := preload("res://ui/block_info/storage_block_info.tscn")
const WEAPON_DETAIL := preload("res://ui/block_info/weapon_block_info.tscn")
const CONTROL_DETAIL := preload("res://ui/block_info/control_block_info.tscn")
const DRILL_DETAIL := preload("res://ui/block_info/drill_block_info.tscn")
const MAINTENANCE_BAY_DETAIL := preload(
	"res://ui/block_info/workshop_block_info.tscn"
)

var target_block: Block
var detail_section: Node

@onready var title_label: Label = $Margin/VBox/Header/Title
@onready var status_label: Label = $Margin/VBox/Status
@onready var detail_host: VBoxContainer = (
	$Margin/VBox/DetailScroll/DetailHost
)

func _ready() -> void:
	hide()

func open_for_block(
	block: Block,
	screen_position: Vector2 = Vector2.ZERO
) -> bool:
	if not is_instance_valid(block) or not block.has_information_panel():
		return false
	_disconnect_target()
	target_block = block
	target_block.health_changed.connect(_refresh_general)
	target_block.block_destroyed.connect(_on_target_destroyed)
	_refresh_general()
	_create_detail_section()
	show()
	move_to_front()
	var viewport_size := get_viewport_rect().size
	size = size.min(viewport_size)
	var target_position := position
	if screen_position != Vector2.ZERO:
		target_position = screen_position + Vector2(16.0, 16.0)
	position = target_position.clamp(
		Vector2.ZERO,
		(viewport_size - size).max(Vector2.ZERO)
	)
	return true

func close_panel() -> void:
	hide()
	_disconnect_target()

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

func _create_detail_section() -> void:
	var detail_scene: PackedScene
	var panel_height := 150.0
	if target_block is ControlBlock:
		detail_scene = CONTROL_DETAIL
		panel_height = 230.0
	elif target_block is Weapon:
		detail_scene = WEAPON_DETAIL
		panel_height = 330.0
	elif target_block.get_information_panel_key() == &"drill":
		detail_scene = DRILL_DETAIL
		panel_height = 210.0
	elif target_block.get_information_panel_key() == &"maintenance_bay":
		detail_scene = MAINTENANCE_BAY_DETAIL
		panel_height = 350.0
	elif target_block is ItemStorage or target_block is LiquidStorage:
		detail_scene = STORAGE_DETAIL
		panel_height = 520.0

	size = Vector2(360.0, panel_height)
	if detail_scene == null:
		return
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
