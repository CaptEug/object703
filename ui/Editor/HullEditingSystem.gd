class_name HullEditingSystem
extends RefCounted

# 引用
var editor: Control
var selected_vehicle: Vehicle
var camera: Camera2D

# 放置状态变量
var current_ghost_block: Node2D = null
var current_block_scene: PackedScene = null
var is_first_block := true
var is_new_vehicle := false

# 吸附系统变量
var current_ghost_connection_index := 0
var current_vehicle_connection_index = 0
var available_ghost_points: Array[Connector] = []
var available_vehicle_points: Array[Connector] = []
var current_snap_config: Dictionary = {}
var snap_config: Dictionary

# 移动功能变量
var is_moving_block := false
var moving_block: Block = null
var moving_block_original_position: Vector2
var moving_block_original_rotation: float
var moving_block_original_grid_positions: Array
var moving_block_ghost: Node2D = null
var moving_snap_config: Dictionary = {}
var is_mouse_pressed := false
var drag_timer: float = 0.0
var is_dragging := false
var DRAG_DELAY: float = 0.2

const GRID_SIZE = 16

func get_viewport():
	return editor.get_viewport()

func get_tree():
	return editor.get_tree()

func setup(editor_ref: Control):
	editor = editor_ref
	selected_vehicle = editor_ref.selected_vehicle
	camera = editor_ref.camera

func handle_left_click():
	if editor.is_ui_interaction:
		return
	
	if current_ghost_block and not editor.is_recycle_mode:
		try_place_block()
	
	if editor.is_recycle_mode:
		try_remove_block()
		return

func process(delta):
	if is_mouse_pressed and not is_dragging:
		drag_timer += delta
		if drag_timer >= DRAG_DELAY:
			is_dragging = true
			_start_block_drag()
	
	if current_ghost_block and Engine.get_frames_drawn() % 2 == 0:
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		update_ghost_block_position(global_mouse_pos)
	
	if is_moving_block and moving_block_ghost:
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		update_moving_block_position(global_mouse_pos)
	
	selected_vehicle = editor.selected_vehicle
	camera = editor.camera

func _start_block_drag():
	if not selected_vehicle:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	var block = get_block_at_position(global_mouse_pos)
	
	if block and block.get_parent() == selected_vehicle:
		start_moving_block(block)

func _end_block_drag():
	if is_moving_block and moving_block:
		if moving_snap_config and not moving_snap_config.is_empty():
			place_moving_block()
		else:
			cancel_moving_block()
	
	is_moving_block = false
	moving_block = null
	if moving_block_ghost:
		moving_block_ghost.queue_free()
		moving_block_ghost = null

func start_moving_block(block: Block):
	if is_moving_block:
		return
	
	moving_block = block
	moving_block_original_position = block.global_position
	moving_block_original_rotation = block.global_rotation
	moving_block_original_grid_positions = get_block_grid_positions(block)
	
	# 创建移动虚影
	moving_block_ghost = block.duplicate()
	get_tree().current_scene.add_child(moving_block_ghost)
	moving_block_ghost.modulate = Color(1, 1, 1, 0.5)
	moving_block_ghost.z_index = 100
	setup_ghost_block_collision(moving_block_ghost)
	
	# 从车辆中移除原块（临时）
	var connections_to_disconnect = find_connections_for_block(block)
	disconnect_connections(connections_to_disconnect)
	
	var control = selected_vehicle.control
	selected_vehicle.remove_block(block, false)
	selected_vehicle.control = control
	
	is_moving_block = true

func update_moving_block_position(mouse_position: Vector2):
	if not is_moving_block or not moving_block_ghost:
		return
	
	available_vehicle_points = selected_vehicle.get_available_points_near_position(mouse_position, 20.0)
	available_ghost_points = get_moving_ghost_available_connection_points()
	
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		moving_block_ghost.global_position = mouse_position
		moving_block_ghost.rotation = moving_block_original_rotation
		moving_block_ghost.modulate = editor.GHOST_FREE_COLOR
		moving_snap_config = {}
		return
	
	moving_snap_config = get_current_snap_config_for_moving()
	
	if moving_snap_config and not moving_snap_config.is_empty():
		moving_block_ghost.global_position = moving_snap_config.ghost_position
		moving_block_ghost.global_rotation = moving_snap_config.ghost_rotation
		moving_block_ghost.modulate = editor.GHOST_SNAP_COLOR
	else:
		moving_block_ghost.global_position = mouse_position
		moving_block_ghost.rotation = moving_block_original_rotation
		moving_block_ghost.modulate = editor.GHOST_FREE_COLOR
		moving_snap_config = {}

func place_moving_block():
	if not is_moving_block or not moving_block or not moving_snap_config:
		return
	
	var grid_positions = moving_snap_config.positions
	
	# 设置新位置和旋转
	moving_block.global_position = moving_snap_config.ghost_position
	moving_block.global_rotation = moving_snap_config.ghost_rotation
	
	# 重新添加到车辆
	var control = selected_vehicle.control
	selected_vehicle._add_block(moving_block, moving_block.position, grid_positions)
	selected_vehicle.control = control
	
	# 建立连接
	if moving_snap_config.has("vehicle_point") and moving_snap_config.has("ghost_point"):
		establish_connection(moving_snap_config.vehicle_point, moving_block, moving_snap_config.ghost_point)
	
	editor.update_blueprint_ghosts()

func cancel_moving_block():
	if not is_moving_block or not moving_block:
		return
	
	# 恢复原位置
	moving_block.global_position = moving_block_original_position
	moving_block.global_rotation = moving_block_original_rotation
	
	# 重新添加到车辆
	var control = selected_vehicle.control
	selected_vehicle._add_block(moving_block, moving_block.position, moving_block_original_grid_positions)
	selected_vehicle.control = control
	
	# 恢复连接
	enable_connection_points_for_blocks([moving_block])

# === 方块放置核心功能 ===
func start_block_placement(scene_path: String):
	if not editor.is_editing or not selected_vehicle:
		return
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	current_block_scene = load(scene_path)
	if not current_block_scene:
		push_error("Unable to load block scene: ", scene_path)
		return
	
	current_ghost_block = current_block_scene.instantiate()
	get_tree().current_scene.add_child(current_ghost_block)
	current_ghost_block.modulate = Color(1, 1, 1, 0.5)
	current_ghost_block.z_index = 100
	current_ghost_block.do_connect = false
	
	current_ghost_block.base_rotation_degree = 0
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)
	
	reset_connection_indices()
	current_snap_config = {}

func setup_ghost_block_collision(ghost: Node2D):
	var collision_shapes = ghost.find_children("*", "CollisionShape2D", true)
	for shape in collision_shapes:
		shape.disabled = true
	
	var collision_polygons = ghost.find_children("*", "CollisionPolygon2D", true)
	for poly in collision_polygons:
		poly.disabled = true
	
	if ghost is RigidBody2D:
		ghost.freeze = true
		ghost.collision_layer = 0
		ghost.collision_mask = 0

func update_ghost_block_position(mouse_position: Vector2):
	if is_first_block and is_new_vehicle:
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = Color(0.8, 0.8, 1.0, 0.5)
		current_snap_config = {}
		return
	
	available_vehicle_points = selected_vehicle.get_available_points_near_position(mouse_position, 20.0)
	available_ghost_points = get_ghost_block_available_connection_points()
	
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = editor.GHOST_FREE_COLOR
		current_snap_config = {}
		return
	
	snap_config = get_current_snap_config()
	
	if snap_config:
		current_ghost_block.global_position = snap_config.ghost_position
		current_ghost_block.global_rotation = snap_config.ghost_rotation
		current_ghost_block.modulate = editor.GHOST_SNAP_COLOR
		current_snap_config = snap_config
	else:
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = editor.GHOST_FREE_COLOR
		current_snap_config = {}

func get_ghost_block_available_connection_points() -> Array[Connector]:
	var points: Array[Connector] = []
	if current_ghost_block:
		var connection_points = current_ghost_block.get_available_connection_points()
		for point in connection_points:
			if point is Connector:
				point.qeck = false
				points.append(point)
	return points

func get_current_snap_config() -> Dictionary:
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		return {}
	var best_config = find_best_snap_config()
	return best_config

func find_best_snap_config() -> Dictionary:
	var best_config = {}
	var min_distance = INF
	var best_ghost_pos = null
	var best_vehicle_pos = null
	
	for vehicle_point in available_vehicle_points:
		var vehicle_block = vehicle_point.find_parent_block()
		if not vehicle_block:
			continue			
		var vehicle_point_global = get_connection_point_global_position(vehicle_point, vehicle_block)
		for ghost_point in available_ghost_points:
			if vehicle_point.connected_to == null:
				vehicle_point.is_connection_enabled = true
			var target_rotation = calculate_aligned_rotation_from_base(vehicle_block)
			if not can_points_connect_with_rotation(vehicle_point, ghost_point, target_rotation):
				continue
				
			var positions = calculate_rotated_grid_positions(vehicle_point, ghost_point)
			if positions is bool:
				continue
			var ghost_local_offset = ghost_point.position.rotated(target_rotation)
			var ghost_position = vehicle_point_global - ghost_local_offset
			var mouse_pos = get_viewport().get_mouse_position()
			var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
			var distance = global_mouse_pos.distance_to(ghost_position)
			if distance < min_distance:
				best_vehicle_pos = vehicle_point
				best_ghost_pos = ghost_point
				min_distance = distance
				best_config = {
					"vehicle_point": vehicle_point,
					"ghost_point": ghost_point,
					"ghost_position": ghost_position,
					"ghost_rotation": target_rotation,
					"vehicle_block": vehicle_block,
					"positions": positions
				}
	
	return best_config

func calculate_aligned_rotation_from_base(vehicle_block: Block) -> float:
	var dir = vehicle_block.base_rotation_degree
	return deg_to_rad(current_ghost_block.base_rotation_degree) + deg_to_rad(-dir) + vehicle_block.global_rotation

func can_points_connect_with_rotation(point_a: Connector, point_b: Connector, ghost_rotation: float) -> bool:
	if point_a.connection_type != point_b.connection_type:
		return false
	if editor.is_editing and not editor.turret_editing_system.is_turret_editing_mode:
		if point_a.layer != 1:
			return false
	if not point_a.is_connection_enabled or not point_b.is_connection_enabled:
		return false
	var ghost_point_direction = point_b.rotation + ghost_rotation
	var angle_diff = are_rotations_opposite_best(ghost_point_direction, point_a.global_rotation)
	return angle_diff

func are_rotations_opposite_best(rot1: float, rot2: float) -> bool:
	var dir1 = Vector2(cos(rot1), sin(rot1))
	var dir2 = Vector2(cos(rot2), sin(rot2))
	
	var dot_product = dir1.dot(dir2)
	return dot_product < -0.9

func get_connection_point_global_position(point: Connector, block: Block) -> Vector2:
	return block.global_position + point.position.rotated(block.global_rotation)

func rotate_ghost_connection():
	if not current_ghost_block:
		return
	
	current_ghost_block.base_rotation_degree += 90
	current_ghost_block.base_rotation_degree = fmod(current_ghost_block.base_rotation_degree + 90, 360) - 90
	
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_ghost_block_position(global_mouse_pos)

func try_place_block():
	if not current_ghost_block or not selected_vehicle:
		return
	
	if is_first_block and is_new_vehicle:
		place_first_block()
		return
	
	if not current_snap_config:
		return
	
	var connections_to_disconnect = find_connections_to_disconnect_for_placement()
	disconnect_connections(connections_to_disconnect)
	
	var grid_positions = snap_config.positions
	var new_block: Block = current_block_scene.instantiate()
	selected_vehicle.add_child(new_block)
	new_block.global_position = current_snap_config.ghost_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	var control = selected_vehicle.control
	selected_vehicle._add_block(new_block, new_block.position, grid_positions)
	selected_vehicle.control = control
	
	start_block_placement_with_rotation(current_block_scene.resource_path)
	
	editor.update_blueprint_ghosts()

func place_first_block():
	var new_block: Block = current_block_scene.instantiate()
	selected_vehicle.add_child(new_block)
	new_block.global_position = current_ghost_block.global_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	
	var grid_positions = calculate_free_grid_positions(new_block)
	
	var control = selected_vehicle.control
	selected_vehicle._add_block(new_block, new_block.position, grid_positions)
	selected_vehicle.control = control
	
	is_first_block = false
	
	start_block_placement_with_rotation(current_block_scene.resource_path)

func calculate_free_grid_positions(block: Block) -> Array:
	var grid_positions = []
	var world_pos = block.global_position
	var grid_x = int(round(world_pos.x / GRID_SIZE))
	var grid_y = int(round(world_pos.y / GRID_SIZE))
	
	var block_size = block.size
	for x in range(block_size.x):
		for y in range(block_size.y):
			var grid_pos: Vector2i
			match int(block.base_rotation_degree):
				0:
					grid_pos = Vector2i(grid_x + x, grid_y + y)
				90:
					grid_pos = Vector2i(grid_x - y, grid_y + x)
				-90:
					grid_pos = Vector2i(grid_x + y, grid_y - x)
				180, -180:
					grid_pos = Vector2i(grid_x - x, grid_y - y)
				_:
					grid_pos = Vector2i(grid_x + x, grid_y + y)
			
			grid_positions.append(grid_pos)
	
	return grid_positions

func start_block_placement_with_rotation(scene_path: String):
	if not editor.is_editing or not selected_vehicle:
		return
	
	var base_rotation_degree = current_ghost_block.base_rotation_degree
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	current_block_scene = load(scene_path)
	if not current_block_scene:
		push_error("无法加载块场景: ", scene_path)
		return
	
	current_ghost_block = current_block_scene.instantiate()
	get_tree().current_scene.add_child(current_ghost_block)
	current_ghost_block.modulate = Color(1, 1, 1, 0.5)
	current_ghost_block.z_index = 100
	current_ghost_block.do_connect = false
	
	current_ghost_block.base_rotation_degree = base_rotation_degree
	current_ghost_block.rotation = deg_to_rad(base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)
	
	reset_connection_indices()
	current_snap_config = {}

func establish_connection(vehicle_point: Connector, new_block: Block, ghost_point: Connector):
	var new_block_points = new_block.find_children("*", "Connector")
	var target_point = null
	
	for point in new_block_points:
		if point is Connector and point.name == ghost_point.name:
			target_point = point
			break
	
	if target_point is Connector:
		target_point.is_connection_enabled = true
		vehicle_point.try_connect(target_point)

func calculate_rotated_grid_positions(vehiclepoint, ghostpoint):
	var grid_positions = []
	var grid_block = {}
	
	if not selected_vehicle:
		return grid_positions
	
	var block_size = current_ghost_block.size

	var location_v = vehiclepoint.location
	
	var rotation_b = vehiclepoint.find_parent_block().base_rotation_degree
	var grid_b = {}
	var grid_b_pos = {}
	
	for key in selected_vehicle.grid:
		if selected_vehicle.grid[key] == vehiclepoint.find_parent_block():
			grid_b[key] = selected_vehicle.grid[key]
	
	grid_b_pos = get_rectangle_corners(grid_b)
	var grid_connect_g
	if grid_b_pos.is_empty():
		return false
	var connect_pos_v
	if rotation_b == 0:
		connect_pos_v = Vector2i(grid_b_pos["1"].x + location_v.x, grid_b_pos["1"].y + location_v.y)
	elif rotation_b == -90:
		connect_pos_v = Vector2i(grid_b_pos["4"].x + location_v.y, grid_b_pos["4"].y - location_v.x)
	elif rotation_b == -180 or rotation_b == 180:
		connect_pos_v = Vector2i(grid_b_pos["3"].x - location_v.x, grid_b_pos["3"].y - location_v.y)
	elif rotation_b == 90:
		connect_pos_v = Vector2i(grid_b_pos["2"].x - location_v.y, grid_b_pos["2"].y + location_v.x)
	grid_connect_g = get_connection_offset(connect_pos_v, vehiclepoint.rotation, vehiclepoint.find_parent_block().base_rotation_degree)
	
	if grid_connect_g != null and block_size != null and ghostpoint.location != null:
		grid_block = to_grid(grid_connect_g, block_size, ghostpoint.location)
	
	for pos in grid_block:
		if selected_vehicle.grid.has(pos):
			return false
		grid_positions.append(pos)
	
	return grid_positions

func get_connection_offset(connect_pos_v: Vector2i, _rotation: float, direction: int) -> Vector2i:
	var rounded_rotation_or = round(rad_to_deg(_rotation))
	var rounded_rotation = direction + rounded_rotation_or
	rounded_rotation = wrapf(rounded_rotation, -180, 180)
	
	if rounded_rotation == 0:
		return Vector2i(connect_pos_v.x + 1, connect_pos_v.y)
	elif rounded_rotation == -90:
		return Vector2i(connect_pos_v.x, connect_pos_v.y - 1)
	elif rounded_rotation == -180 or rounded_rotation == 180:
		return Vector2i(connect_pos_v.x - 1, connect_pos_v.y)
	elif rounded_rotation == 90:
		return Vector2i(connect_pos_v.x, connect_pos_v.y + 1)
	
	return connect_pos_v

func get_rectangle_corners(grid_data: Dictionary) -> Dictionary:
	if grid_data.is_empty():
		return {}
	
	var x_coords = []
	var y_coords = []
	
	for coord in grid_data.keys():
		x_coords.append(coord[0])
		y_coords.append(coord[1])
	
	x_coords.sort()
	y_coords.sort()
	
	var min_x = x_coords[0]
	var max_x = x_coords[x_coords.size() - 1]
	var min_y = y_coords[0]
	var max_y = y_coords[y_coords.size() - 1]
	
	var corners = {
		"1": Vector2i(min_x, min_y),
		"2": Vector2i(max_x, min_y),
		"3": Vector2i(max_x, max_y),
		"4": Vector2i(min_x, max_y)
	}
	
	return corners

func to_grid(grid_connect_g: Vector2i, block_size: Vector2i, connect_pos_g: Vector2i) -> Dictionary:
	var grid_block = {}
	for i in block_size.x:
		for j in block_size.y:
			if current_ghost_block.base_rotation_degree == 0:
				var left_up = Vector2i(grid_connect_g.x - connect_pos_g.x, grid_connect_g.y - connect_pos_g.y)
				grid_block[Vector2i(left_up.x + i, left_up.y + j)] = current_ghost_block
			elif current_ghost_block.base_rotation_degree == -90:
				var left_up = Vector2i(grid_connect_g.x - connect_pos_g.y, grid_connect_g.y + connect_pos_g.x)
				grid_block[Vector2i(left_up.x + j, left_up.y - i)] = current_ghost_block
			elif current_ghost_block.base_rotation_degree == -180 or current_ghost_block.base_rotation_degree == 180:
				var left_up = Vector2i(grid_connect_g.x + connect_pos_g.x, grid_connect_g.y + connect_pos_g.y)
				grid_block[Vector2i(left_up.x - i, left_up.y - j)] = current_ghost_block
			elif current_ghost_block.base_rotation_degree == 90:
				var left_up = Vector2i(grid_connect_g.x + connect_pos_g.y, grid_connect_g.y - connect_pos_g.x)
				grid_block[Vector2i(left_up.x - j, left_up.y + i)] = current_ghost_block
	return grid_block

func find_connections_to_disconnect_for_placement() -> Array:
	var connections_to_disconnect = []
	if current_snap_config.vehicle_point and current_snap_config.vehicle_point.connected_to:
		connections_to_disconnect.append({
			"from": current_snap_config.vehicle_point,
			"to": current_snap_config.vehicle_point.connected_to
		})
	return connections_to_disconnect

func disconnect_connections(connections: Array):
	for connection in connections:
		if is_instance_valid(connection.from):
			connection.from.disconnect_joint()
		if is_instance_valid(connection.to):
			connection.to.disconnect_joint()

func get_affected_blocks() -> Array:
	var affected_blocks = []
	if current_snap_config.vehicle_point:
		var parent_block = current_snap_config.vehicle_point.find_parent_block()
		if parent_block:
			affected_blocks.append(parent_block)
	return affected_blocks

func enable_connection_points_for_blocks(blocks: Array):
	for block in blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point):
					point.set_connection_enabled(true)

# === 删除模式功能 ===
func try_remove_block():
	if not selected_vehicle:
		return
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = global_mouse_pos
	query.collision_mask = 1
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is Block and block.get_parent() == selected_vehicle:			
			var block_name = block.block_name
			var connections_to_disconnect = find_connections_for_block(block)
			disconnect_connections(connections_to_disconnect)
			var control = selected_vehicle.control
			selected_vehicle.remove_block(block, true)
			selected_vehicle.control = control
			enable_connection_points_for_blocks(get_affected_blocks_for_removal(block))
			call_deferred("check_vehicle_stability")
			
			editor.update_blueprint_ghosts()
			var block_count_after = selected_vehicle.blocks.size()
			if block_count_after == 0:
				is_first_block = true
				is_new_vehicle = true 
			break

func find_connections_for_block(block: Block) -> Array:
	var connections = []
	for point in block.connection_points:
		if point.connected_to:
			connections.append({
				"from": point,
				"to": point.connected_to
			})
	return connections

func get_affected_blocks_for_removal(removed_block: Block) -> Array:
	var affected_blocks = []
	for point in removed_block.connection_points:
		if point.connected_to:
			var connected_block = point.connected_to.find_parent_block()
			if connected_block:
				affected_blocks.append(connected_block)
	return affected_blocks

func cancel_placement():
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	current_block_scene = null
	current_snap_config = {}
	editor.clear_tab_container_selection()
	editor.update_vehicle_info_display()

func get_block_at_position(position: Vector2) -> Block:
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 1
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is Block and block.get_parent() == selected_vehicle:
			return block
	return null

func get_block_grid_positions(block: Block) -> Array:
	var grid_positions = []
	
	for grid_pos in selected_vehicle.grid:
		if selected_vehicle.grid[grid_pos] == block:
			grid_positions.append(grid_pos)
	
	return grid_positions

func get_current_snap_config_for_moving() -> Dictionary:
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		return {}
	
	var original_ghost = current_ghost_block
	current_ghost_block = moving_block_ghost
	
	var best_config = find_best_snap_config()
	
	current_ghost_block = original_ghost
	
	return best_config

func get_moving_ghost_available_connection_points() -> Array[Connector]:
	var points: Array[Connector] = []
	if moving_block_ghost:
		var connection_points = moving_block_ghost.get_available_connection_points()
		for point in connection_points:
			if point is Connector:
				point.qeck = false
				points.append(point)
	return points

func enable_all_connection_points_for_editing(open: bool):
	if not selected_vehicle:
		return
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point):
					point.set_connection_enabled(open)

func restore_original_connections():
	if not selected_vehicle:
		return
	
	enable_all_connection_points_for_editing(false)
	await get_tree().process_frame

func reset_connection_indices():
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0

func check_vehicle_stability():
	if selected_vehicle:
		selected_vehicle.check_and_regroup_disconnected_blocks()
