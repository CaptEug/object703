class_name Explosion
extends Area2D

@export var radius: int = 0
@export var max_damage: float = 0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	var shape := collision_shape.shape as CircleShape2D
	shape.radius = maxf(radius * Globals.TILE_SIZE, 1.0)
	
	call_deferred("apply_explosion")


func apply_explosion() -> void:
	for body in get_overlapping_bodies():
		if body is Vehicle:
			apply_explosion_to_vehicle(body as Vehicle)
	for wall_node: Node in get_tree().get_nodes_in_group(
		"world_block_layers"
	):
		if wall_node is WorldBlockLayer:
			(wall_node as WorldBlockLayer).apply_radial_damage(
				global_position,
				radius,
				max_damage
			)
	
	queue_free()


func apply_explosion_to_vehicle(vehicle: Vehicle) -> void:
	var center_cell: Vector2i = vehicle.world_to_cell(global_position)
	var hit_blocks: Dictionary = {}
	if radius <= 0:
		var direct_block := vehicle.get_block(center_cell)
		if direct_block != null:
			vehicle.damage_block_at(
				direct_block.origin_cell,
				max_damage,
				&"EXPLOSIVE"
			)
		return
	
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var offset := Vector2i(x, y)
			var cell := center_cell + offset
			
			var cell_world := vehicle.cell_to_world(cell) + Vector2.ONE * (Globals.TILE_SIZE * 0.5)
			var dist := global_position.distance_to(cell_world) / float(Globals.TILE_SIZE)
			
			if dist > radius:
				continue
			
			var factor := 1.0 - (dist / float(radius))
			var damage := int(round(max_damage * factor))
			if damage <= 0:
				continue
			
			var block := vehicle.get_block(cell)
			if block == null:
				continue
			
			if hit_blocks.has(block):
				hit_blocks[block] = max(hit_blocks[block], damage)
			else:
				hit_blocks[block] = damage
	
	for block in hit_blocks.keys():
		vehicle.damage_block_at(
			(block as Block).origin_cell,
			float(hit_blocks[block]),
			&"EXPLOSIVE"
		)
