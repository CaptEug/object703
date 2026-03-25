class_name Track
extends Block


var drive_force : float = 0.0
@export var max_force : float = 100.0
@export var grip : float = 0.8
@export var slip_threshold : float = 100.0
@export var shaft_port : Vector2i = Vector2i.ZERO

@export var track_sprite : Sprite2D
@export var sprite_mask : Sprite2D
@export var mask_front : CompressedTexture2D
@export var mask_back : CompressedTexture2D
@export var mask_single : CompressedTexture2D
@onready var sprite_origin : Vector2 = track_sprite.texture.region.position
var connected_tracks: Array[Track] = []
var front_track: Track = null
var back_track: Track = null
var scroll: float = 0.0


func _physics_process(delta):
	if vehicle:
		update_scroll(delta)
		update_track_sprite()
		if absf(drive_force) > 0.0001:
			apply_drive_force()
		apply_side_friction()


# Physics

func apply_drive_force():
	var forward = -global_transform.y
	var vehicle_vel = vehicle.linear_velocity
	# lateral slip (sideways movement)
	var sideways_speed = vehicle_vel.dot(global_transform.x)
	var slip_factor = clamp(1.0 - abs(sideways_speed) / slip_threshold, 0.2, 1.0)
	var traction = grip * slip_factor
	var force = forward * drive_force  * traction
	var offset := global_position - vehicle.global_position
	vehicle.apply_force(force, offset)


func apply_side_friction():
	var sideways = global_transform.x
	var vel = vehicle.linear_velocity
	var side_speed = vel.dot(sideways)
	var friction_force = -sideways * side_speed * grip
	vehicle.apply_force(friction_force, position)


# Visual
func get_forward_cell_dir() -> Vector2i:
	match rotation_index % 4:
		0: return Vector2i(0, -1)
		1: return Vector2i(1, 0)
		2: return Vector2i(0, 1)
		3: return Vector2i(-1, 0)
	return Vector2i(0, -1)


func get_track_at(cell: Vector2i) -> Track:
	var other = vehicle.get_block(cell)
	if other == null:
		return null
	if not (other is Track):
		return null
	var t := other as Track
	# use exact rotation if you want strict line continuity
	if t.rotation_index != rotation_index:
		return null
	return t


func update_local_neighbors() -> void:
	var dir := get_forward_cell_dir()
	front_track = get_track_at(origin_cell + dir)
	back_track = get_track_at(origin_cell - dir)
	update_mask()


func update_mask():
	if front_track and back_track:
		sprite_mask.texture = null
	elif front_track:
		sprite_mask.texture = mask_back
	elif back_track:
		sprite_mask.texture = mask_front
	else:
		sprite_mask.texture = mask_single


func update_scroll(delta) -> void:
	var offset := global_position - vehicle.to_global(vehicle.center_of_mass)
	# point velocity = linear + angular contribution
	var tangent := Vector2(-offset.y, offset.x) * vehicle.angular_velocity
	var point_velocity := vehicle.linear_velocity + tangent
	var drive_dir := (-global_transform.y).normalized()
	scroll += point_velocity.dot(drive_dir) * delta / grip


func get_average_track_scroll() -> float:
	if connected_tracks.is_empty():
		return 0.0
	var total := 0.0
	for track in connected_tracks:
		total += track.scroll
	return total / float(connected_tracks.size())


func update_track_sprite() -> void:
	var average_scroll = get_average_track_scroll()
	# Wrap around texture region vertically
	var wrapped_y = wrapf(average_scroll, 0, TILE_SIZE * size.y)
	# Update the region's position
	track_sprite.texture.region.position = sprite_origin + Vector2(0, wrapped_y)
