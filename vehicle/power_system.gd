class_name PowerSystem
extends Node2D

@export var vehicle : Vehicle

var shaft_scene : PackedScene = load("res://blocks/mobility/power_shaft.tscn")
var shaft_grid : Dictionary[Vector2i, Shaft] = { }   # Cell -> shaft
var shaft_groups: Array[Array] = []

var block_group_map: Dictionary[Block, int] = {}  # block -> group_index

var avaliable_engines : Array[PowerPack] = []
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
	update_power_system()


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


func rebuild_shaft_network() -> void:
	shaft_groups = rebuild_shaft_groups()
	block_group_map.clear()
	avaliable_engines.clear()
	active_tracks.clear()
	
	for group_index in range(shaft_groups.size()):
		var group_set := {}
		for cell in shaft_groups[group_index]:
			group_set[cell] = true
		for block in vehicle.blocks:
			if "shaft_port" in block:
				var world_port: Vector2i = block.get_transformed_cell(block.shaft_port)
				if group_set.has(world_port):
					block_group_map[block] = group_index
					
					if block is PowerPack:
						avaliable_engines.append(block)
					
					if block is Track:
						if active_tracks.has(block):
							continue
						for track in block.connected_tracks:
							block_group_map[track] = group_index
							active_tracks.append(track)


# =========================
# DISTRIBUTION BUILD
# =========================

func rebuild_drive_distribution() -> void:
	move_coeffs.clear()
	pivot_coeffs.clear()
	rebuild_shaft_network()
	
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
# UPDATE POWER SYSTEM
# =========================

func get_group_power(group_index:int) -> float:
	var group_power := 0.0
	for engine in avaliable_engines:
		if block_group_map.get(engine, -1) != group_index:
			continue
		group_power += engine.power_output
	
	return group_power


func get_group_cmd_sum(group_index: int, raw_cmds: Dictionary[Track, float]) -> float:
	var sum := 0.0
	
	for track in active_tracks:
		if block_group_map.get(track, -1) != group_index:
			continue
		sum += absf(raw_cmds.get(track, 0.0))
	
	return sum


func get_device_power_demand(group_index: int) -> float:
	var demand := 0.0
	
	for block in block_group_map.keys():
		if block_group_map[block] != group_index:
			continue
		if block is PowerPack:
			continue
		if block is Track:
			continue
		
		if block.has_method("get_power_demand"):
			demand += block.get_power_demand()
	
	return demand


func get_track_scale_limit(group_index: int, raw_cmds: Dictionary[Track, float]) -> float:
	var limit := INF
	
	for track in active_tracks:
		if block_group_map.get(track, -1) != group_index:
			continue
		var cmd: float = raw_cmds.get(track, 0.0)
		if absf(cmd) == 0.0:
			continue
		var track_limit := track.max_force / absf(cmd)
		limit = minf(limit, track_limit)
	
	return limit


func get_track_power_demand(group_index: int, raw_cmds: Dictionary[Track, float], scale_limit: float) -> float:
	var power_demand := 0.0
	if scale_limit == INF:
		scale_limit = 0.0
	
	for track in active_tracks:
		if block_group_map.get(track, -1) != group_index:
			continue
		var cmd: float = raw_cmds.get(track, 0.0)
		power_demand += abs(cmd) * scale_limit
	
	return power_demand


func distribute_device_power(group_index: int, power_budget:float) -> float:
	return 0.0


func distribute_track_power(raw_cmds: Dictionary[Track, float], power_scale: float) -> void:
	for track in active_tracks:
		var cmd: float = raw_cmds.get(track, 0.0)
		track.drive_force = cmd * power_scale


func update_engine_targets(group_index: int, group_used_power: float) -> void:
	var group_engines: Array[PowerPack] = []
	
	for engine in avaliable_engines:
		if block_group_map.get(engine, -1) == group_index:
			engine.power_target = 0.0
			group_engines.append(engine)
	
	var remaining := group_used_power
	var active: Array[PowerPack] = group_engines.duplicate()
	
	while remaining > 0.0 and not active.is_empty():
		var share := remaining / active.size()
		var next_active: Array[PowerPack] = []
		var given_this_round := 0.0
		
		for engine in active:
			var headroom := engine.max_power - engine.power_target
			if headroom <= 0.0:
				continue
			
			var give := minf(share, headroom)
			engine.power_target += give
			given_this_round += give
			
			if engine.max_power - engine.power_target > 0.0:
				next_active.append(engine)
		
		if given_this_round <= 0.0:
			break
		
		remaining -= given_this_round
		active = next_active


func update_power_system() -> void:
	if shaft_groups.is_empty():
		return
	
	var drive_input := vehicle.get_drive_input()
	var move_input: float = drive_input["move"]
	var pivot_input: float = drive_input["pivot"]
	var raw_cmds: Dictionary[Track, float] = {}
	
	for track in active_tracks:
		var move_c: float = move_coeffs.get(track, 0.0)
		var pivot_c: float = pivot_coeffs.get(track, 0.0)
		raw_cmds[track] = move_input * move_c + pivot_input * pivot_c
	
	var final_power_scale := INF
	
	for group_index in range(shaft_groups.size()):
		# Update Engine Targets Based On Power Demands
		var device_demand: float = get_device_power_demand(group_index)
		
		var track_limit := get_track_scale_limit(group_index, raw_cmds)
		var track_demand: float = get_track_power_demand(group_index, raw_cmds, track_limit)
		
		update_engine_targets(group_index, device_demand + track_demand)
		
		# Findout Track Power Scale
		var group_power := get_group_power(group_index)
		var device_used: float = distribute_device_power(group_index, group_power)
		var remaining_power := maxf(0.0, group_power - device_used)
		var track_cmd_sum: float = get_group_cmd_sum(group_index, raw_cmds)
		
		var power_limit := remaining_power / track_cmd_sum
		var group_scale := minf(power_limit, track_limit)
		
		final_power_scale = minf(final_power_scale, group_scale)
	
	if final_power_scale == INF:
		final_power_scale = 0.0
	
	final_power_scale = maxf(final_power_scale, 0.0)
	
	# apply the same scale to all groups, then update engines
	distribute_track_power(raw_cmds, final_power_scale)
