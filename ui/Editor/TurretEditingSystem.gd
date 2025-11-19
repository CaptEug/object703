class_name TurretEditingSystem
extends RefCounted

# 引用
var editor: Control
var selected_vehicle: Vehicle
var camera: Camera2D

# 炮塔编辑状态变量
var is_turret_editing_mode := false
var current_editing_turret: TurretRing = null
var current_ghost_block: Node2D = null
var current_block_scene: PackedScene = null

# 炮塔吸附系统变量
var available_turret_connectors: Array[TurretConnector] = []
var available_block_connectors: Array[TurretConnector] = []
var turret_snap_config: Dictionary = {}

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
	
	var mouse_pos = get_viewport().get_mouse_position()  # 使用 get_viewport()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	if current_ghost_block:
		var can_place = turret_snap_config and not turret_snap_config.is_empty()
		
		if can_place and not editor.is_recycle_mode:
			try_place_turret_block()
		elif editor.is_recycle_mode:
			try_remove_turret_block()
	else:
		if editor.is_recycle_mode:
			try_remove_turret_block()
		
		var clicked_turret = get_turret_at_position(global_mouse_pos)
		if clicked_turret and clicked_turret != current_editing_turret:
			exit_turret_editing_mode()
			enter_turret_editing_mode(clicked_turret)

func process(delta):
	if is_turret_editing_mode and current_ghost_block:
		update_turret_placement_feedback()
	
	selected_vehicle = editor.selected_vehicle
	camera = editor.camera

# === 炮塔编辑模式功能 ===
func enter_turret_editing_mode(turret: TurretRing):
	if is_turret_editing_mode:
		exit_turret_editing_mode()
	
	print("=== 进入炮塔编辑模式 ===")
	print("   目标炮塔:", turret.block_name if turret else "null")
	
	is_turret_editing_mode = true
	current_editing_turret = turret
	
	# 启用炮塔连接点
	for point in turret.turret_basket.get_children():
		if point is TurretConnector:
			if point.connected_to == null:
				point.is_connection_enabled = true
	
	reset_turret_rotation(turret)
	disable_turret_rotation(turret)
	
	# 设置块的颜色状态
	editor.reset_all_blocks_color()
	
	if current_ghost_block:
		current_ghost_block.visible = false
	
	if editor.is_recycle_mode:
		Input.set_custom_mouse_cursor(editor.saw_cursor)
		print("炮塔编辑模式：删除功能已切换到炮塔专用")
	
	editor.clear_tab_container_selection()
	
	print("炮塔编辑模式进入完成")

func exit_turret_editing_mode():
	if not is_turret_editing_mode:
		return
	
	print("=== 退出炮塔编辑模式 ===")
	
	is_turret_editing_mode = false
	
	if current_editing_turret:
		enable_turret_rotation(current_editing_turret)
	
	Input.set_custom_mouse_cursor(null)
	
	# 恢复所有块的颜色
	if selected_vehicle:
		for block in selected_vehicle.blocks:
			if is_instance_valid(block):
				block.modulate = Color.WHITE
	
	if editor.is_recycle_mode:
		Input.set_custom_mouse_cursor(editor.saw_cursor)
	
	turret_snap_config = {}
	available_turret_connectors.clear()
	available_block_connectors.clear()
	
	if current_ghost_block:
		current_ghost_block.visible = true
	
	current_editing_turret = null
	
	print("炮塔编辑模式退出完成")

func reset_turret_rotation(turret: TurretRing):
	if turret and is_instance_valid(turret):
		turret.reset_turret_rotation()

func disable_turret_rotation(turret: TurretRing):
	if turret and is_instance_valid(turret):
		turret.lock_turret_rotation()

func enable_turret_rotation(turret: TurretRing):
	if turret and is_instance_valid(turret):
		turret.unlock_turret_rotation()

# === 方块放置功能 ===
func start_block_placement(scene_path: String):
	if not is_turret_editing_mode or not selected_vehicle:
		return
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	current_block_scene = load(scene_path)
	if not current_block_scene:
		push_error("Unable to load block scene: ", scene_path)
		return
	
	current_ghost_block = current_block_scene.instantiate()
	get_tree().current_scene.add_child(current_ghost_block)  # 使用 get_tree()
	current_ghost_block.modulate = Color(1, 1, 1, 0.5)
	current_ghost_block.z_index = 100
	current_ghost_block.do_connect = false
	
	# 在炮塔编辑模式下设置碰撞层
	if current_ghost_block is CollisionObject2D:
		current_ghost_block.set_layer(2)
		current_ghost_block.collision_mask = 2
	
	current_ghost_block.base_rotation_degree = 0
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)
	
	turret_snap_config = {}

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

func rotate_ghost_connection():
	if not current_ghost_block:
		return
	
	current_ghost_block.base_rotation_degree += 90
	current_ghost_block.base_rotation_degree = fmod(current_ghost_block.base_rotation_degree + 90, 360) - 90
	
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	var mouse_pos = get_viewport().get_mouse_position()  # 使用 get_viewport()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_turret_placement_feedback()

func cancel_placement():
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	current_block_scene = null
	turret_snap_config = {}
	editor.clear_tab_container_selection()
	editor.update_vehicle_info_display()

# === 炮塔编辑模式吸附系统 ===
func update_turret_placement_feedback():
	if not is_turret_editing_mode or not current_ghost_block or not current_editing_turret:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()  # 使用 get_viewport()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	update_turret_editing_snap_system(global_mouse_pos)

func update_turret_editing_snap_system(mouse_position: Vector2):
	if not is_turret_editing_mode or not current_ghost_block or not current_editing_turret:
		set_ghost_free_position(mouse_position)
		return
	
	var in_range = is_position_in_turret_range_for_ghost(mouse_position)
	
	if in_range:
		update_turret_range_placement(mouse_position)
	else:
		update_outside_turret_placement(mouse_position)

func is_position_in_turret_range_for_ghost(mouse_position: Vector2) -> bool:
	if not current_editing_turret or not current_ghost_block:
		return false
	
	var turret_use = current_editing_turret.turret_basket
	var local_mouse_pos = turret_use.to_local(mouse_position)
	
	var turret_width = current_editing_turret.size.x * GRID_SIZE
	var turret_height = current_editing_turret.size.y * GRID_SIZE
	var turret_half_width = turret_width / 2.0
	var turret_half_height = turret_height / 2.0
	
	var is_in_turret_area = (
		local_mouse_pos.x >= -turret_half_width and 
		local_mouse_pos.x <= turret_half_width and 
		local_mouse_pos.y >= -turret_half_height and 
		local_mouse_pos.y <= turret_half_height
	)
	
	if not is_in_turret_area:
		return false
	
	var grid_x = int(floor(local_mouse_pos.x / GRID_SIZE))
	var grid_y = int(floor(local_mouse_pos.y / GRID_SIZE))
	
	var adjusted_grid_x = grid_x
	var adjusted_grid_y = grid_y
	
	var ghost_grid_positions = calculate_ghost_grid_positions_for_turret(
		Vector2i(adjusted_grid_x, adjusted_grid_y), 
		current_ghost_block.base_rotation_degree
	)
	
	for pos in ghost_grid_positions:
		if not current_editing_turret.is_position_available(pos):
			return false
	
	return true

func calculate_ghost_grid_positions_for_turret(base_pos: Vector2i, rotation_deg: float) -> Array:
	var grid_positions = []
	var block_size = current_ghost_block.size
	
	for x in range(block_size.x):
		for y in range(block_size.y):
			var grid_pos: Vector2i
			
			match int(rotation_deg):
				0:
					grid_pos = base_pos + Vector2i(x, y)
				90:
					grid_pos = base_pos + Vector2i(-y, x)
				-90, 270:
					grid_pos = base_pos + Vector2i(y, -x)
				180, -180:
					grid_pos = base_pos + Vector2i(-x, -y)
				_:
					grid_pos = base_pos + Vector2i(x, y)
			
			grid_positions.append(grid_pos)
	
	return grid_positions

func update_turret_range_placement(mouse_position: Vector2):
	var available_turret_points = get_turret_platform_connectors()
	var available_ghost_points_ = get_ghost_block_rigidbody_connectors()
	
	if available_turret_points.is_empty() or available_ghost_points_.is_empty():
		set_ghost_free_position(mouse_position)
		return
		
	var best_snap = find_best_rigidbody_snap_config(mouse_position, available_turret_points, available_ghost_points_)
	
	if best_snap and not best_snap.is_empty():
		apply_turret_snap_config(best_snap)
	else:
		set_ghost_free_position(mouse_position)

func update_outside_turret_placement(mouse_position: Vector2):
	var available_block_points = get_turret_block_connection_points()
	var available_ghost_points_ = get_ghost_block_connection_points()
	
	if available_block_points.is_empty() or available_ghost_points_.is_empty():
		set_ghost_free_position(mouse_position)
		return
	
	var best_snap = find_best_regular_snap_config_for_turret(mouse_position, available_block_points, available_ghost_points_)
	
	if best_snap and not best_snap.is_empty():
		apply_turret_snap_config(best_snap)
	else:
		set_ghost_free_position(mouse_position)

func get_turret_connection_point_global_position(point: Connector, block: Block) -> Vector2:
	return block.global_position + point.position.rotated(block.global_rotation)

# === 删除模式功能 ===
func try_remove_turret_block():
	print("=== 尝试从炮塔移除block ===")
	
	if not is_turret_editing_mode:
		print("❌ 不在炮塔编辑模式")
		return
		
	if not current_editing_turret:
		print("❌ 没有当前编辑的炮塔")
		return
		
	var mouse_pos = get_viewport().get_mouse_position()  # 使用 get_viewport()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	var block_to_remove = get_turret_block_at_position(global_mouse_pos)
	
	if block_to_remove and block_to_remove != current_editing_turret:
		print("✅ 准备移除块:", block_to_remove.block_name)
		current_editing_turret.remove_block_from_turret(block_to_remove)
		print("✅ 块移除完成")
	else:
		if not block_to_remove:
			print("❌ 没有找到要删除的块")
		elif block_to_remove == current_editing_turret:
			print("⚠️ 不能删除炮塔座圈本身")

func get_turret_block_at_position(position: Vector2) -> Block:
	var space_state = get_tree().root.get_world_2d().direct_space_state  # 使用 get_tree()
	var query = PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 2
	
	var result = space_state.intersect_point(query)
	
	for collision in result:
		var block = collision.collider
		
		if (block is Block and 
			block != current_editing_turret and 
			is_block_on_turret(block)):
			return block
			
	return null

func is_block_on_turret(block: Block) -> bool:
	if not current_editing_turret:
		return false
	
	var attached_blocks = current_editing_turret.get_attached_blocks()
	return block in attached_blocks

# === 炮塔放置功能 ===
func try_place_turret_block():
	if not is_turret_editing_mode or not current_editing_turret:
		print("❌ 不在炮塔编辑模式或没有当前编辑的炮塔")
		return
	
	if not current_block_scene:
		print("❌ 没有当前块场景")
		return
	
	if not turret_snap_config or turret_snap_config.is_empty():
		print("❌ 没有吸附配置")
		return
	
	print("=== 炮塔编辑模式放置 ===")
	
	if not turret_snap_config.has("ghost_position"):
		print("❌ 吸附配置缺少位置信息")
		return
	
	var grid_positions = null
	if turret_snap_config.has("grid_positions"):
		grid_positions = turret_snap_config.grid_positions
	elif turret_snap_config.has("positions"):
		grid_positions = turret_snap_config.positions
	else:
		print("❌ 吸附配置缺少网格位置信息")
		return
	
	if not grid_positions or grid_positions.is_empty():
		print("❌ 网格位置为空")
		return
	
	print("✅ 网格位置:", grid_positions)
	
	var new_block: Block = current_block_scene.instantiate()
	
	if new_block is CollisionObject2D:
		new_block.set_layer(2)
		new_block.collision_mask = 2
	
	new_block.global_position = turret_snap_config.ghost_position
	new_block.global_rotation = turret_snap_config.ghost_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	
	if turret_snap_config.has("grid_positions"):
		print("✅ 添加块到炮塔，网格位置: ", turret_snap_config.grid_positions)
		current_editing_turret.add_block_to_turret(new_block, turret_snap_config.grid_positions)
	else:
		print("❌ 吸附配置缺少网格位置信息")
		new_block.queue_free()
		return
	
	if new_block.has_method("connect_aready"):
		await new_block.connect_aready()
	else:
		await get_tree().process_frame
	
	if selected_vehicle:
		selected_vehicle.update_vehicle()
	
	start_block_placement_with_rotation(current_block_scene.resource_path)

func start_block_placement_with_rotation(scene_path: String):
	if not is_turret_editing_mode or not selected_vehicle:
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
	get_tree().current_scene.add_child(current_ghost_block)  # 使用 get_tree()
	current_ghost_block.modulate = Color(1, 1, 1, 0.5)
	current_ghost_block.z_index = 100
	current_ghost_block.do_connect = false
	
	if current_ghost_block is CollisionObject2D:
		current_ghost_block.set_layer(2)
		current_ghost_block.collision_mask = 2
	
	current_ghost_block.base_rotation_degree = base_rotation_degree
	current_ghost_block.rotation = deg_to_rad(base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)
	
	turret_snap_config = {}

func instance_from_id(instance_id: int) -> Object:
	return instance_from_id(instance_id)

func handle_block_colors_in_turret_mode(block: Block):
	if block == current_editing_turret:
		block.modulate = Color.WHITE
		for child in block.turret_basket.get_children():
			if child is Block:
				child.modulate = Color.WHITE
	elif current_editing_turret.turret_blocks.has(block):
		block.modulate = Color.WHITE
	else:
		block.modulate = editor.BLOCK_DIM_COLOR
		if block is TurretRing:
			for child in block.turret_basket.get_children():
				if child is Block:
					child.modulate = editor.BLOCK_DIM_COLOR

# === 炮塔检测功能 ===
func get_turret_at_position(position: Vector2) -> TurretRing:
	var space_state = get_tree().root.get_world_2d().direct_space_state  # 使用 get_tree()
	var query = PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 1
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is TurretRing and block.get_parent() == selected_vehicle:
			return block
	return null

# === 吸附系统辅助函数 ===
func find_best_regular_snap_config_for_turret(mouse_position: Vector2, block_points: Array[Connector], ghost_points: Array[Connector]) -> Dictionary:
	var best_config = {}
	var min_distance = INF
	var SNAP_DISTANCE = 16.0
	
	for block_point in block_points:
		var block = block_point.find_parent_block()
		if not block:
			continue
		
		if block == current_editing_turret:
			print("跳过炮塔座圈本身的连接点")
			continue
			
		var block_point_global = get_turret_connection_point_global_position(block_point, block)
		
		for ghost_point in ghost_points:
			var target_rotation = calculate_aligned_rotation_for_turret_block(block)
			
			if not can_points_connect_with_rotation_for_turret(block_point, ghost_point, target_rotation):
				continue
				
			var positions = calculate_rotated_grid_positions_for_turret(block_point, ghost_point)
			if positions is bool or positions.is_empty():
				continue
				
			var ghost_local_offset = ghost_point.position.rotated(target_rotation)
			var ghost_position = block_point_global - ghost_local_offset
			
			var distance = mouse_position.distance_to(ghost_position)
			
			if distance < SNAP_DISTANCE and distance < min_distance:
				min_distance = distance
				best_config = {
					"vehicle_point": block_point,
					"ghost_point": ghost_point,
					"ghost_position": ghost_position,
					"ghost_rotation": target_rotation,
					"vehicle_block": block,
					"positions": positions,
					"grid_positions": positions
				}
		
	return best_config

func calculate_aligned_rotation_for_turret_block(vehicle_block: Block) -> float:
	var world_rotation = vehicle_block.global_rotation
	var self_rotation = deg_to_rad(vehicle_block.base_rotation_degree)
	var base_rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	return world_rotation + base_rotation - self_rotation

func can_points_connect_with_rotation_for_turret(point_a: Connector, point_b: Connector, ghost_rotation: float) -> bool:
	if point_a.connection_type != point_b.connection_type:
		return false
	if not point_a.is_connection_enabled or not point_b.is_connection_enabled:
		return false
	
	var ghost_point_direction = point_b.rotation + ghost_rotation
	var vehicle_point_direction = point_a.global_rotation
	
	var can_connect = are_rotations_opposite_best(ghost_point_direction, vehicle_point_direction)
	return can_connect

func are_rotations_opposite_best(rot1: float, rot2: float) -> bool:
	var dir1 = Vector2(cos(rot1), sin(rot1))
	var dir2 = Vector2(cos(rot2), sin(rot2))
	
	var dot_product = dir1.dot(dir2)
	return dot_product < -0.9

func calculate_rotated_grid_positions_for_turret(turret_point: Connector, ghost_point: Connector):
	var grid_positions = []
	var grid_block = {}
	
	if not current_editing_turret:
		return grid_positions
	
	var block_size = ghost_point.find_parent_block().size

	var location_v = turret_point.location
	
	var rotation_b = turret_point.find_parent_block().base_rotation_degree
	var grid_b = {}
	var grid_b_pos = {}
	
	for key in current_editing_turret.turret_grid:
		if current_editing_turret.turret_grid[key] == turret_point.find_parent_block():
			grid_b[key] = current_editing_turret.turret_grid[key]
	
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
	grid_connect_g = get_connection_offset(connect_pos_v, turret_point.rotation, turret_point.find_parent_block().base_rotation_degree)
	
	if grid_connect_g != null and block_size != null and ghost_point.location != null:
		grid_block = to_grid(grid_connect_g, block_size, ghost_point.location)
	
	for pos in grid_block:
		if current_editing_turret.turret_grid.has(pos):
			return false
		grid_positions.append(pos)
	
	return grid_positions

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

func get_turret_platform_connectors() -> Array[TurretConnector]:
	var points: Array[TurretConnector] = []
	
	if not current_editing_turret:
		return points
	
	var connectors = current_editing_turret.turret_basket.get_children()
	for connector in connectors:
		if (connector is TurretConnector and 
			connector.is_connection_enabled and 
			connector.connected_to == null):
			points.append(connector)
	
	return points

func get_turret_block_connection_points() -> Array[Connector]:
	var points: Array[Connector] = []
	
	if not current_editing_turret:
		return points
	
	var attached_blocks = current_editing_turret.get_attached_blocks()
	
	for block in attached_blocks:
		if is_instance_valid(block):
			if block == current_editing_turret:
				print("跳过炮塔座圈本身")
				continue
				
			var available_points = 0
			for point in block.connection_points:
				if (point is Connector and 
					point.is_connection_enabled and 
					point.connected_to == null):
					points.append(point)
					available_points += 1
	return points
	
func get_ghost_block_rigidbody_connectors() -> Array[TurretConnector]:
	var points: Array[TurretConnector] = []
	
	if not current_ghost_block:
		return points
	
	var connectors = current_ghost_block.find_children("*", "TurretConnector", true)
	for connector in connectors:
		if (connector is TurretConnector and 
			connector.is_connection_enabled and 
			connector.connected_to == null):
			points.append(connector)
	
	return points

func get_ghost_block_connection_points() -> Array[Connector]:
	var points: Array[Connector] = []
	if current_ghost_block:
		var connection_points = current_ghost_block.get_available_connection_points()
		for point in connection_points:
			if point is Connector:
				point.qeck = false
				points.append(point)
	return points

func find_best_rigidbody_snap_config(mouse_position: Vector2, turret_points: Array[TurretConnector], ghost_points: Array[TurretConnector]) -> Dictionary:
	var best_config = {}
	var min_distance = INF
	
	for turret_point in turret_points:
		for ghost_point in ghost_points:
			if not can_rigidbody_connectors_connect(turret_point, ghost_point):
				continue
			
			var snap_config = calculate_rigidbody_snap_config(turret_point, ghost_point)
			if snap_config.is_empty():
				continue
			
			var target_position = snap_config.get("ghost_position", Vector2.ZERO)
			var distance = mouse_position.distance_to(target_position)
			
			if distance < turret_point.snap_distance_threshold and distance < min_distance:
				min_distance = distance
				best_config = snap_config
	
	return best_config

func calculate_rigidbody_snap_config(turret_point: TurretConnector, ghost_point: TurretConnector) -> Dictionary:
	if not turret_point or not ghost_point:
		return {}
	
	if not current_ghost_block:
		return {}
	
	if not current_editing_turret:
		return {}
	
	var turret_world_pos = turret_point.global_position
	var turret_grid_pos = Vector2i(turret_point.location.x, turret_point.location.y)
	
	var ghost_local_pos = ghost_point.position
	var ghost_grid_pos = Vector2i(ghost_point.location.x, ghost_point.location.y)
	
	var target_rotation = calculate_turret_block_rotation(turret_point, ghost_point)
	
	var base_grid_pos = turret_point.location
	
	var grid_positions = calculate_all_grid_positions(base_grid_pos, current_ghost_block.size, ghost_point)
	
	if not are_turret_grid_positions_available(grid_positions, current_editing_turret):
		return {}
	
	var world_position = calculate_turret_world_position(turret_point, ghost_local_pos, deg_to_rad(ghost_point.get_parent().base_rotation_degree))
	
	var snap_config = {
		"turret_point": turret_point,
		"ghost_point": ghost_point,
		"ghost_position": world_position,
		"ghost_rotation": target_rotation,
		"rotation": target_rotation,
		"grid_positions": grid_positions,
		"positions": grid_positions,
		"base_grid_pos": base_grid_pos,
		"connection_type": "rigidbody"
	}
	
	return snap_config

func calculate_all_grid_positions(base_pos: Vector2i, block_size: Vector2i, ghost_point: TurretConnector) -> Array:
	var positions = []
	var local_pos = ghost_point.location
	var zero_pos = Vector2i.ZERO
	match int(ghost_point.get_parent().base_rotation_degree):
		0:
			zero_pos = base_pos - local_pos
		90:
			zero_pos = base_pos + Vector2i(local_pos.y, -local_pos.x)
		-90, 270:
			zero_pos = base_pos + Vector2i(-local_pos.y, local_pos.x)
		180, -180:
			zero_pos = base_pos + Vector2i(local_pos.x, local_pos.y)
		_:
			zero_pos = base_pos - local_pos
	for i in block_size.x:
		for j in block_size.y:
			var one_point
			match int(ghost_point.get_parent().base_rotation_degree):
				0:
					one_point = Vector2i(zero_pos.x + i, zero_pos.y + j)
				90:
					one_point = Vector2i(zero_pos.x - j, zero_pos.y + i)
				-90, 270:
					one_point = Vector2i(zero_pos.x + j, zero_pos.y - i)
				180, -180:
					one_point = Vector2i(zero_pos.x - i, zero_pos.y - j)
			positions.append(one_point)
	return positions

func calculate_turret_world_position(turret_point: TurretConnector, ghost_local_pos: Vector2, rotation: float) -> Vector2:
	var use_pos = turret_point.position - ghost_local_pos.rotated(rotation)
	return turret_point.get_parent().to_global(use_pos)

func calculate_turret_block_rotation(turret_point: TurretConnector, ghost_point: TurretConnector) -> float:
	var turret_direction = turret_point.global_rotation
	var ghost_base_rotation = deg_to_rad(ghost_point.get_parent().base_rotation_degree)
	var ghost_direction = ghost_base_rotation
	
	var relative_rotation = turret_direction + ghost_direction
	
	return relative_rotation

func can_rigidbody_connectors_connect(connector_a: TurretConnector, connector_b: TurretConnector) -> bool:
	if not connector_a or not connector_b:
		return false
	
	if connector_a.connection_type != connector_b.connection_type:
		return false
	
	if not connector_a.is_connection_enabled or not connector_b.is_connection_enabled:
		return false
	
	if connector_a.connected_to != null or connector_b.connected_to != null:
		return false
	
	var a_is_turret = connector_a.get_parent() is Block
	var b_is_turret = connector_b.get_parent() is Block
	
	return a_is_turret != b_is_turret

func are_turret_grid_positions_available(grid_positions: Array, turret: TurretRing) -> bool:
	for pos in grid_positions:
		if pos:
			if not turret.is_position_available(pos):
				return false
	return true

func apply_turret_snap_config(snap_config: Dictionary):
	if not snap_config.has("ghost_position"):
		print("❌ 吸附配置缺少 ghost_position")
		return
	
	current_ghost_block.global_position = snap_config.ghost_position
	
	if snap_config.has("ghost_rotation"):
		current_ghost_block.global_rotation = snap_config.ghost_rotation
	else:
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
	
	current_ghost_block.modulate = editor.GHOST_SNAP_COLOR
	
	turret_snap_config = snap_config.duplicate()

func set_ghost_free_position(mouse_position: Vector2):
	current_ghost_block.global_position = mouse_position
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
	current_ghost_block.modulate = editor.GHOST_FREE_COLOR
	turret_snap_config = {}
