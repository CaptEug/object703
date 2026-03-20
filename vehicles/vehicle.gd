class_name Vehicle
extends RigidBody2D

const TILE_SIZE := Globals.TILE_SIZE

@onready var tilemap : TileMapLayer = $TileMapLayer
@onready var blocks_root : Node2D = $Blocks

# grid storage
var grid : Dictionary = {}      # Vector2i -> Block
var blocks : Array = []

# basic property
var total_mass := 0.0
var total_engine_power: float = 0.0
var engines: Array[Engine] = []
var tracks: Array[Track] = []
var move_coeffs: Dictionary = {}   # Track -> float
var pivot_coeffs: Dictionary = {}   # Track -> float

func _process(_delta):
	apply_drive_input()


func update_vehicle():
	refresh_system_lists()
	center_of_mass = calculate_center_of_mass()
	var mass_sum := 0
	for block in blocks:
		mass_sum += block.mass
	total_mass = mass_sum
	rebuild_drive_distribution()


func get_drive_input() -> Dictionary:
	var v := 0.0
	if Input.is_action_pressed("FORWARD"):
		v += 1.0
	if Input.is_action_pressed("BACKWARD"):
		v -= 1.0
	
	var h := 0.0
	if Input.is_action_pressed("PIVOT_RIGHT"):
		h += 1.0
	if Input.is_action_pressed("PIVOT_LEFT"):
		h -= 1.0
	
	var input = {
		"move": clampf(v, -1.0, 1.0),
		"pivot": clamp(h, -1.0, 1.0)
		}
	
	return input


# Block Management

func can_place_block(block:Block, cell:Vector2i) -> bool:
	block.origin_cell = cell
	for c in block.get_occupied_cells():
		if grid.has(c):
			block.queue_free()
			return false
	return true


func place_block(block_prototype:Block, cell:Vector2i, rotation_i:int):
	var block := block_prototype.duplicate() as Block
	block.update_transform(self, cell, rotation_i)
	# check space
	if not can_place_block(block, cell):
		block.queue_free()
		return false
	# register cells
	for c in block.get_occupied_cells():
		grid[c] = block
	
	blocks_root.add_child(block)
	blocks.append(block)
	create_collision(block)
	
	update_vehicle()
	
	return true


func create_collision(block:Block):
	if block.collision != null:
		block.remove_child(block.collision)
		block.collision.position = block.position
		add_child(block.collision)


func destroy_block(block:Block):
	blocks.erase(block)
	for c in block.get_occupied_cells():
		grid.erase(c)
	block.collision.queue_free()
	block.queue_free()
	
	update_vehicle()


func get_block(cell:Vector2i):
	if grid.has(cell):
		return grid[cell]
	return null


func refresh_system_lists() -> void:
	tracks.clear()
	engines.clear()
	total_engine_power = 1000.0
	for block in blocks:
		if block is Track:
			tracks.append(block as Track)
		elif block is Engine:
			var engine := block as Engine
			engines.append(engine)
			total_engine_power += engine.power_output


# Physics Calculation

func calculate_center_of_mass() -> Vector2:
	if blocks.size() == 0:
		return Vector2.ZERO
	
	var weighted_sum := Vector2.ZERO
	var total_m := 0.0
	
	for block in blocks:
		var block_mass = block.mass
		# center position of the block
		var block_center = (block.origin_cell * TILE_SIZE) + (block.size * TILE_SIZE) / 2
		weighted_sum += Vector2(block_center) * block_mass
		total_m += block_mass
	
	return weighted_sum / total_m


func rebuild_drive_distribution() -> void:
	move_coeffs.clear()
	pivot_coeffs.clear()
	
	if tracks.is_empty():
		return
	
	var data := []
	for track in tracks:
		var r: Vector2 = track.position - center_of_mass
		var d: Vector2 = Vector2.UP.rotated(track.rotation).normalized()
		var move := d.dot(Vector2.UP)
		var tau := r.cross(d)
	
		data.append({
			"track": track,
			"move": move,
			"tau": tau
		})
	
	var move_target := Vector2(1.0, 0.0)
	var pivot_target := Vector2(0.0, 1.0)
	var move_solution := solve_distribution(data, move_target)
	var pivot_solution := solve_distribution(data, pivot_target)
	
	for i in range(data.size()):
		var track: Track = data[i]["track"]
		move_coeffs[track] = move_solution[i]
		pivot_coeffs[track] = pivot_solution[i]


func solve_distribution(data: Array, target: Vector2) -> Array:
	var coeffs: Array = []
	# A A^T for 2xN system
	var m00 := 0.0
	var m01 := 0.0
	var m11 := 0.0
	
	for item in data:
		var move: float = item["move"]
		var tau: float = item["tau"]
		m00 += move * move
		m01 += move * tau
		m11 += tau * tau
	
	var det := m00 * m11 - m01 * m01
	
	if absf(det) == 0:
		print("NOT INVERTIBLE 2x2 MATRIX")
		for i in range(data.size()):
			coeffs.append(0.0)
		return coeffs
	
	var inv_det := 1.0 / det
	
	# inverse of [[m00, m01], [m01, m11]]
	var i00 :=  m11 * inv_det
	var i01 := -m01 * inv_det
	var i10 := -m01 * inv_det
	var i11 :=  m00 * inv_det
	
	# lambda = inv(A A^T) * target
	var l0 := i00 * target.x + i01 * target.y
	var l1 := i10 * target.x + i11 * target.y
	
	# c = A^T * lambda
	for item in data:
		var move: float = item["move"]
		var tau: float = item["tau"]
		var c := move * l0 + tau * l1
		coeffs.append(c)
	
	return normalize_coeffs_abs(coeffs)


func normalize_coeffs_abs(coeffs: Array) -> Array:
	var out: Array = []
	var abs_sum := 0.0
	for c in coeffs:
		abs_sum += absf(c)
	if abs_sum <= 0.000001:
		for c in coeffs:
			out.append(0.0)
		return out
	for c in coeffs:
		out.append(c / abs_sum)
	return out


func apply_drive_input() -> void:
	if tracks.is_empty():
		return
	
	var drive_input := get_drive_input()
	var move_input: float = drive_input["move"]
	var pivot_input: float = drive_input["pivot"]
	var raw_commands: Array[float] = []
	var total_abs := 0.0
	
	for track in tracks:
		var move_c: float = move_coeffs.get(track, 0.0)
		var pivot_c: float = pivot_coeffs.get(track, 0.0)
		var cmd := move_input * move_c + pivot_input * pivot_c
		raw_commands.append(cmd)
		total_abs += absf(cmd)
	
	if total_abs <= 0.0001:
		for track in tracks:
			track.drive_force = 0.0
		return
	
	var scale_by_power := total_engine_power / total_abs
	var scale_by_track := INF
	
	for i in range(tracks.size()):
		var cmd := raw_commands[i]
		var track: Track = tracks[i]
		if absf(cmd) > 0.0001:
			scale_by_track = minf(scale_by_track, track.max_force / absf(cmd))
	
	var final_scale := minf(scale_by_power, scale_by_track)
	
	for i in range(tracks.size()):
		var track: Track = tracks[i]
		track.drive_force = raw_commands[i] * final_scale


# Convert world position to vehicle grid cell
func world_to_cell(world_pos: Vector2) -> Vector2i:
	var local = to_local(world_pos)
	return Vector2i(
		floor(local.x / TILE_SIZE),
		floor(local.y / TILE_SIZE)
	)


# Convert cell → world position (for preview drawing)
func cell_to_world(cell: Vector2i) -> Vector2:
	var local = cell * TILE_SIZE
	return to_global(local)
