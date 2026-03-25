extends Node2D

@export var vehicle : Vehicle

var shaft_scene : PackedScene = load("res://blocks/mobility/power_shaft.tscn")
var shaft_grid : Dictionary[Vector2i, Shaft] = { }   # Cell -> shaft
var shaft_groups: Array[Array] = []

var block_group_map: Dictionary[Block, int] = {}  # block -> group_index
var group_power_map: Dictionary[int, float] = {}  # group_index -> power

var active_tracks : Array[Track] = []
var move_coeffs: Dictionary[Track, float] = {}
var pivot_coeffs: Dictionary[Track, float] = {}

const DIRS := [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT
]


func _ready():
	pass

func _process(_delta):
	apply_drive_input()


func can_palce_shaft(cell:Vector2i) -> bool:
	# must on block
	if not vehicle.grid.has(cell):
		return false
	# check occupied
	if shaft_grid.has(cell):
		return false
	return true


func place_shaft(cell:Vector2i):
	if not can_palce_shaft(cell):
		return
	var shaft := shaft_scene.instantiate() as Shaft
	shaft.update_transform(vehicle, cell, 0)
	add_child(shaft)
	
	shaft_grid[cell] = shaft
	
	rebuild_drive_distribution()


func remove_shaft(cell:Vector2i):
	if shaft_grid.has(cell):
		shaft_grid[cell].queue_free()
		shaft_grid.erase(cell)
	
	rebuild_drive_distribution()

 
func update_shaft_visuals():
	for shaft in shaft_grid.values():
		shaft.update_sprite()  


# =========================
# SHAFT GROUP BUILD
# =========================

func rebuild_shaft_groups() -> Array[Array]:
	update_shaft_visuals()
	var groups: Array[Array] = []
	var visited := {}
	for start_cell in shaft_grid.keys():
		if visited.has(start_cell):
			continue
		var group: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start_cell]
		visited[start_cell] = true
		
		while queue.size() > 0:
			var cell: Vector2i = queue.pop_front()
			group.append(cell)
			for dir in DIRS:
				var next: Vector2i = cell + dir
				if not shaft_grid.has(next):
					continue
				if visited.has(next):
					continue
				visited[next] = true
				queue.append(next)
		
		groups.append(group)
	
	return groups


func rebuild_block_group_map() -> void:
	shaft_groups = rebuild_shaft_groups()
	block_group_map.clear()
	active_tracks.clear()
	
	for group_index in range(shaft_groups.size()):
		var group_set := {}
		for cell in shaft_groups[group_index]:
			group_set[cell] = true
		for block in vehicle.blocks:
			if "shaft_port" in block:
				var world_port: Vector2i = block.get_transformd_cell(block.shaft_port)
				if group_set.has(world_port):
					block_group_map[block] = group_index
					if block is Track:
						active_tracks.append(block)
						for track in block.connected_tracks:
							if not block_group_map.has(track):
								block_group_map[track] = group_index
								active_tracks.append(track)


func rebuild_group_power_map() -> void:
	group_power_map.clear()
	rebuild_block_group_map()
	
	for group_index in range(shaft_groups.size()):
		group_power_map[group_index] = 0.0
	
	for engine in vehicle.engines:
		var group_index: int = block_group_map.get(engine, -1)
		if group_index == -1:
			continue
		group_power_map[group_index] += engine.power_output


# =========================
# DISTRIBUTION BUILD
# =========================

func rebuild_drive_distribution() -> void:
	move_coeffs.clear()
	pivot_coeffs.clear()
	rebuild_group_power_map()
	
	if active_tracks.is_empty():
		return
	
	var data := []
	for track in active_tracks:
		var r: Vector2 = track.position - vehicle.center_of_mass
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
		for i in range(data.size()):
			coeffs.append(1.0 / data.size())
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
	for c in coeffs:
		out.append(c / abs_sum)
	return out


# =========================
# APPLY INPUT
# =========================

func apply_drive_input() -> void:
	if active_tracks.is_empty():
		return
	
	var drive_input := vehicle.get_drive_input()
	var move_input: float = drive_input["move"]
	var pivot_input: float = drive_input["pivot"]
	var raw_cmds : Dictionary[Track, float] = {}
	
	for track in active_tracks:
		var move_c: float = move_coeffs.get(track, 0.0)
		var pivot_c: float = pivot_coeffs.get(track, 0.0)
		var cmd := move_input * move_c + pivot_input * pivot_c
		raw_cmds[track] = cmd
	
	var final_scale := INF
	
	for group_index in range(shaft_groups.size()):
		var group_cmd_sum := 0.0
		var group_track_limit := INF
		for track in active_tracks:
			if block_group_map.get(track, -1) != group_index:
				continue
			var cmd: float = raw_cmds[track]
			group_cmd_sum += absf(cmd)
			var track_limit := track.max_force / absf(cmd)
			group_track_limit = minf(group_track_limit, track_limit)
		
		var group_power: float = group_power_map.get(group_index, 0.0)
		var group_power_limit := group_power / group_cmd_sum
		var group_scale := minf(group_power_limit, group_track_limit)
		
		final_scale = minf(final_scale, group_scale)
	
	if final_scale == INF:
		final_scale = 0.0
	
	for track in active_tracks:
		var cmd: float = raw_cmds.get(track, 0.0)
		track.drive_force = cmd * final_scale
