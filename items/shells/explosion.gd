class_name Explosion
extends Area2D

@export var radius: int = 0
@export var max_damage: float = 0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	var shape := collision_shape.shape as CircleShape2D
	shape.radius = radius * Globals.TILE_SIZE
	
	call_deferred("apply_explosion")


func apply_explosion() -> void:
	for body in get_overlapping_bodies():
		if body is Vehicle:
			apply_explosion_to_vehicle(body as Vehicle)
	
	queue_free()


func apply_explosion_to_vehicle(vehicle: Vehicle) -> void:
	var center_cell: Vector2i = vehicle.world_to_cell(global_position)
	var hit_blocks: Dictionary = {}
	
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
		block.damage(hit_blocks[block], "EXPLOSIVE")
