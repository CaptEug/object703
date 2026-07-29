class_name Projectile
extends RigidBody2D

enum ShellType {
	AP,
	HE,
	APHE,
}

@export var shell_type: ShellType = ShellType.AP
@export var weight: float = 1.0
@export var max_K_DMG: float = 0.0
@export var max_E_DMG: float = 100.0
@export var explosion_radius: int = 3
@export var max_range: int = 100 # tiles
@export var ricochet_angle: float = 70.0 # degrees away from surface normal
@export_range(0.0, 1.0, 0.01) var ricochet_loss: float = 0.5

var source_vehicle: Vehicle
var source_weapon: Weapon
var spawn_position := Vector2.ZERO
var distance_travelled := 0.0
var remaining_K_DMG := 0.0

var last_pos := Vector2.ZERO
var source_cleared := false
var traversing_vehicle: Vehicle
var penetrated_block_ids: Dictionary = {}

var explosion_scene := preload("res://items/shells/explosion.tscn")

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	mass = weight
	last_pos = global_position
	if spawn_position == Vector2.ZERO:
		spawn_position = global_position
	remaining_K_DMG = maxf(max_K_DMG, 0.0)
	var shell_body := get_node_or_null("Area2D") as Area2D
	if shell_body != null:
		shell_body.monitoring = false
		shell_body.monitorable = false

func _physics_process(_delta: float) -> void:
	var from := last_pos
	var to := global_position
	var step_distance := from.distance_to(to)
	if step_distance <= 0.001:
		return

	distance_travelled += step_distance
	if not source_cleared:
		source_cleared = spawn_position.distance_to(to) >= Globals.TILE_SIZE * 2.0

	var max_distance := maxf(float(max_range), 1.0) * Globals.TILE_SIZE
	if distance_travelled > max_distance:
		queue_free()
		return

	if is_instance_valid(traversing_vehicle):
		if _trace_vehicle_cells(traversing_vehicle, from, to, Vector2.ZERO):
			return
		if traversing_vehicle.get_block(traversing_vehicle.world_to_cell(to)) != null:
			last_pos = to
			return

	var exclusions: Array[RID] = [get_rid()]
	if not source_cleared and is_instance_valid(source_vehicle):
		exclusions.append(source_vehicle.get_rid())
	if is_instance_valid(traversing_vehicle):
		exclusions.append(traversing_vehicle.get_rid())
	traversing_vehicle = null

	var query := PhysicsRayQueryParameters2D.create(from, to, 3, exclusions)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		last_pos = to
		return

	var collider: Object = hit.get("collider")
	var hit_position: Vector2 = hit.get("position", to)
	var hit_normal: Vector2 = hit.get("normal", Vector2.ZERO)
	if collider is Vehicle:
		traversing_vehicle = collider as Vehicle
		if _trace_vehicle_cells(
			traversing_vehicle,
			hit_position + (to - from).normalized() * 0.5,
			to,
			hit_normal
		):
			return
	elif collider is WallLayer:
		_handle_wall_impact(
			collider as WallLayer,
			hit_position,
			hit_normal,
			(to - from).normalized()
		)
		return
	else:
		_handle_world_impact(hit_position, hit_normal)
		return

	last_pos = to

func _trace_vehicle_cells(
	target_vehicle: Vehicle,
	from: Vector2,
	to: Vector2,
	entry_normal: Vector2
) -> bool:
	var distance := from.distance_to(to)
	var sample_step := maxf(Globals.TILE_SIZE * 0.2, 1.0)
	var sample_count := maxi(1, ceili(distance / sample_step))
	var first_new_block := true

	for index in range(sample_count + 1):
		var ratio := float(index) / float(sample_count)
		var sample_position := from.lerp(to, ratio)
		var block := target_vehicle.get_block(target_vehicle.world_to_cell(sample_position))
		if block == null:
			continue
		var block_id := block.get_instance_id()
		if penetrated_block_ids.has(block_id):
			continue

		if first_new_block and not entry_normal.is_zero_approx():
			if shell_type != ShellType.HE and _should_ricochet(
				(to - from).normalized(),
				entry_normal
			):
				ricochet(entry_normal, sample_position)
				return true
		first_new_block = false
		penetrated_block_ids[block_id] = true

		if shell_type == ShellType.HE:
			global_position = sample_position
			explode()
			queue_free()
			return true

		var kinetic_resistance := maxf(block.k_a, 0.001)
		var damage_needed := maxf(block.hp, 0.0) / kinetic_resistance
		var kinetic_spent := minf(remaining_K_DMG, damage_needed)
		block.damage(kinetic_spent, "KINETIC")
		remaining_K_DMG = maxf(remaining_K_DMG - kinetic_spent, 0.0)

		if remaining_K_DMG <= 0.001:
			global_position = sample_position
			if shell_type == ShellType.APHE:
				explode()
			queue_free()
			return true

	return false

func _should_ricochet(direction: Vector2, normal: Vector2) -> bool:
	if direction.is_zero_approx() or normal.is_zero_approx():
		return false
	var normal_alignment := clampf(direction.normalized().dot(-normal.normalized()), -1.0, 1.0)
	var incidence_degrees := rad_to_deg(acos(normal_alignment))
	return incidence_degrees >= ricochet_angle

func ricochet(normal: Vector2, hit_position: Vector2) -> void:
	linear_velocity = linear_velocity.bounce(normal) * ricochet_loss
	remaining_K_DMG *= ricochet_loss
	global_position = hit_position + normal * 1.0
	rotation = linear_velocity.angle() + PI * 0.5
	last_pos = global_position
	traversing_vehicle = null


func _handle_wall_impact(
	wall: WallLayer,
	hit_position: Vector2,
	hit_normal: Vector2,
	direction: Vector2
) -> void:
	if (
		shell_type != ShellType.HE
		and _should_ricochet(direction, hit_normal)
	):
		ricochet(hit_normal, hit_position)
		return

	var cell := wall.get_solid_cell_at_world_position(
		hit_position,
		direction
	)
	if cell == WallLayer.INVALID_CELL:
		_handle_world_impact(hit_position, hit_normal)
		return

	var impact_position := hit_position
	if not direction.is_zero_approx():
		impact_position += direction.normalized()
	global_position = impact_position
	if shell_type == ShellType.HE:
		explode()
		queue_free()
		return

	var result := wall.damage_tile(
		cell,
		remaining_K_DMG,
		&"KINETIC"
	)
	if not result["hit"]:
		_handle_world_impact(hit_position, hit_normal)
		return

	remaining_K_DMG = maxf(
		remaining_K_DMG - float(result["damage_consumed"]),
		0.0
	)
	if result["destroyed"] and remaining_K_DMG > 0.001:
		last_pos = global_position
		return

	if shell_type == ShellType.APHE:
		explode()
	queue_free()


func _handle_world_impact(hit_position: Vector2, hit_normal: Vector2) -> void:
	if shell_type != ShellType.HE and _should_ricochet(
		linear_velocity.normalized(),
		hit_normal
	):
		ricochet(hit_normal, hit_position)
		return
	global_position = hit_position
	if shell_type == ShellType.HE or shell_type == ShellType.APHE:
		explode()
	queue_free()

func explode() -> void:
	var explosion := explosion_scene.instantiate() as Explosion
	if explosion == null:
		return
	explosion.global_position = global_position
	explosion.radius = explosion_radius
	explosion.max_damage = max_E_DMG
	get_tree().current_scene.add_child(explosion)
