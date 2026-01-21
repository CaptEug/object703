class_name BuildingHullEditingSystem
extends RefCounted

# 引用
var editor: BuildingEditor
var selected_building: Building
var camera: Camera2D
var tile: TileMapLayer

# 放置状态变量
var current_ghost_block: Node2D = null
var current_block_scene: PackedScene = null
var is_first_block := true
var is_new_building := false

# 吸附系统变量
var current_ghost_connection_index := 0
var current_building_connection_index = 0
var available_ghost_points: Array[Connector] = []
var available_building_points: Array[Connector] = []
var current_snap_config: Dictionary = {}
var snap_config: Dictionary

const GRID_SIZE = 16

func get_viewport():
	return editor.get_viewport()

func get_tree():
	return editor.get_tree()

func setup(editor_ref: BuildingEditor):
	editor = editor_ref
	selected_building = editor_ref.selected_building
	camera = editor_ref.camera
	tile = editor_ref.tilemap_layer

func handle_left_click():
	if editor.is_ui_interaction:
		return
	
	if current_ghost_block and not editor.is_recycle_mode:
		try_place_block()
	
	if editor.is_recycle_mode:
		try_remove_block()
		return

func process(delta):
	# 确保引用最新
	selected_building = editor.selected_building
	camera = editor.camera
	
	# 更新虚影位置
	if current_ghost_block and Engine.get_frames_drawn() % 2 == 0:
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		update_ghost_block_position(global_mouse_pos)

# === 方块放置核心功能 ===
func start_block_placement(scene_path: String):
	if not editor.is_editing or not selected_building:
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
	
	# 立即更新一次位置
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_ghost_block_position(global_mouse_pos)

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
	if mouse_position != null and tile != null:
		mouse_position = tile.map_to_local(tile.local_to_map(mouse_position)) 
	var a
	var b
	if current_ghost_block.rotation_degrees == 90 or -90:
		if current_ghost_block.size.x % 2 == 0:
			mouse_position.y += 8
		if current_ghost_block.size.y % 2 == 0:
			mouse_position.x += 8
	else :
		if current_ghost_block.size.x % 2 == 0:
			mouse_position.x += 8
		if current_ghost_block.size.y % 2 == 0:
			mouse_position.y += 8
	
	if not current_ghost_block or not selected_building:
		return
	
	if is_first_block and is_new_building:
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
		current_ghost_block.modulate = Color(0.8, 0.8, 1.0, 0.5)
		current_snap_config = {}
		return
	
	available_building_points = selected_building.get_available_points_near_position(mouse_position, 20.0)
	available_ghost_points = get_ghost_block_available_connection_points()
	
	if available_building_points.is_empty() or available_ghost_points.is_empty():
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
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
	if available_building_points.is_empty() or available_ghost_points.is_empty():
		return {}
	var best_config = find_best_snap_config()
	return best_config

func find_best_snap_config() -> Dictionary:
	var best_config = {}
	var min_distance = INF
	var best_ghost_pos = null
	var best_building_pos = null
	
	for building_point in available_building_points:
		var building_block = building_point.find_parent_block()
		if not building_block:
			continue			
		var building_point_global = get_connection_point_global_position(building_point, building_block)
		for ghost_point in available_ghost_points:
			if building_point.connected_to == null:
				building_point.is_connection_enabled = true
			var target_rotation = calculate_aligned_rotation_from_base(building_block)
			if not can_points_connect_with_rotation(building_point, ghost_point, target_rotation):
				continue
				
			var positions = calculate_rotated_grid_positions(building_point, ghost_point)
			if positions is bool:
				continue
			var ghost_local_offset = ghost_point.position.rotated(target_rotation)
			var ghost_position = building_point_global - ghost_local_offset
			var mouse_pos = get_viewport().get_mouse_position()
			var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
			var distance = global_mouse_pos.distance_to(ghost_position)
			if distance < min_distance:
				best_building_pos = building_point
				best_ghost_pos = ghost_point
				min_distance = distance
				best_config = {
					"building_point": building_point,
					"ghost_point": ghost_point,
					"ghost_position": ghost_position,
					"ghost_rotation": target_rotation,
					"building_block": building_block,
					"positions": positions
				}
	
	return best_config

func calculate_aligned_rotation_from_base(building_block: Block) -> float:
	var dir = building_block.base_rotation_degree
	return deg_to_rad(current_ghost_block.base_rotation_degree) + deg_to_rad(-dir) + building_block.global_rotation

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
	if not current_ghost_block or not selected_building:
		return
	
	if is_first_block and is_new_building:
		place_first_block()
		return
	
	if not current_snap_config:
		return
	
	var connections_to_disconnect = find_connections_to_disconnect_for_placement()
	disconnect_connections(connections_to_disconnect)
	
	var grid_positions = snap_config.positions
	var new_block: Block = current_block_scene.instantiate()
	selected_building.add_child(new_block)
	new_block.global_position = current_snap_config.ghost_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	
	selected_building._add_block(new_block, new_block.position, grid_positions)
	new_block.freeze_mode =RigidBody2D.FREEZE_MODE_KINEMATIC
	new_block.freeze = true
	start_block_placement_with_rotation(current_block_scene.resource_path)
	
	editor.update_blueprint_ghosts()

func place_first_block():
	var new_block: Block = current_block_scene.instantiate()
	selected_building.add_child(new_block)
	new_block.global_position = current_ghost_block.global_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	
	var grid_positions = calculate_free_grid_positions(new_block)
	
	selected_building._add_block(new_block, new_block.position, grid_positions)
	
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
	if not editor.is_editing or not selected_building:
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
	
	# 立即更新一次位置
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_ghost_block_position(global_mouse_pos)

func establish_connection(building_point: Connector, new_block: Block, ghost_point: Connector):
	var new_block_points = new_block.find_children("*", "Connector")
	var target_point = null
	
	for point in new_block_points:
		if point is Connector and point.name == ghost_point.name:
			target_point = point
			break
	
	if target_point is Connector:
		target_point.is_connection_enabled = true
		building_point.try_connect(target_point)

func calculate_rotated_grid_positions(buildingpoint, ghostpoint):
	var grid_positions = []
	var grid_block = {}
	
	if not selected_building:
		return grid_positions
	
	var block_size = current_ghost_block.size

	var location_v = buildingpoint.location
	
	var rotation_b = buildingpoint.find_parent_block().base_rotation_degree
	var grid_b = {}
	var grid_b_pos = {}
	
	for key in selected_building.grid:
		if selected_building.grid[key] == buildingpoint.find_parent_block():
			grid_b[key] = selected_building.grid[key]
	
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
	grid_connect_g = get_connection_offset(connect_pos_v, buildingpoint.rotation, buildingpoint.find_parent_block().base_rotation_degree)
	
	if grid_connect_g != null and block_size != null and ghostpoint.location != null:
		grid_block = to_grid(grid_connect_g, block_size, ghostpoint.location)
	
	for pos in grid_block:
		if selected_building.grid.has(pos):
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
	if current_snap_config.building_point and current_snap_config.building_point.connected_to:
		connections_to_disconnect.append({
			"from": current_snap_config.building_point,
			"to": current_snap_config.building_point.connected_to
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
	if current_snap_config.building_point:
		var parent_block = current_snap_config.building_point.find_parent_block()
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
	if not selected_building:
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
		if block is Block and block.get_parent() == selected_building:			
			var connections_to_disconnect = find_connections_for_block(block)
			disconnect_connections(connections_to_disconnect)
			selected_building.remove_block(block, true)
			enable_connection_points_for_blocks(get_affected_blocks_for_removal(block))
			call_deferred("check_building_stability")
			
			editor.update_blueprint_ghosts()
			var block_count_after = selected_building.blocks.size()
			if block_count_after == 0:
				is_first_block = true
				is_new_building = true 
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
	editor.update_building_info_display()

func get_block_at_position(position: Vector2) -> Block:
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 1
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is Block and block.get_parent() == selected_building:
			return block
	return null

func enable_all_connection_points_for_editing(open: bool):
	if not selected_building:
		return
	
	for block in selected_building.blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point):
					point.set_connection_enabled(open)

func restore_original_connections():
	if not selected_building:
		return
	
	enable_all_connection_points_for_editing(false)
	await get_tree().process_frame

func reset_connection_indices():
	current_ghost_connection_index = 0
	current_building_connection_index = 0

func check_building_stability():
	if selected_building:
		selected_building.check_and_regroup_disconnected_blocks()
