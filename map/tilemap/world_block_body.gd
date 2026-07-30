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
