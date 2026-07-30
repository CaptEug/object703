class_name Building
extends RefCounted

var building_name := "New Building"
var owner_id: StringName = &"player"
var block_anchors: Array[Vector2i] = []
var occupied_cells: Array[Vector2i] = []
var functional_blocks: Array[Block] = []


func has_aim_command() -> bool:
	return false


func get_aim_target() -> Vector2:
	return Vector2.ZERO


func get_fire_command() -> bool:
	return false


func can_supply_item(
	_requester: Block,
	_item_name: String,
	_amount: int
) -> bool:
	return false


func supply_item(
	_requester: Block,
	_item_name: String,
	_amount: int
) -> bool:
	return false


func can_supply_liquids(
	_requester: Block,
	_liquid_requests: Dictionary
) -> bool:
	return false


func supply_liquids(
	_requester: Block,
	_liquid_requests: Dictionary
) -> bool:
	return false
