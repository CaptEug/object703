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
const MAX_SNAP_DISTANCE = 50

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
	
	var mouse_pos = get_viewport().get_mouse_position()
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
		else:
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
	
	is_turret_editing_mode = true
	current_editing_turret = turret
	
	# 启用炮塔连接点
	for body in turret.turret_basket.get_children():
		if body is StaticBody2D:
			for point in body.get_children():
				if point is TurretConnector and point.connected_to == null:
					point.is_connection_enabled = true
	
	for block:Block in turret.turret_blocks:
		for point in block.get_children():
			if point is Connector and point.connected_to == null:
				point.is_connection_enabled = true
	
	turret.lock_turret_rotation()
	
	if current_ghost_block:
		current_ghost_block.visible = false
	
	if editor.is_recycle_mode:
		Input.set_custom_mouse_cursor(editor.saw_cursor)
	
	editor.clear_tab_container_selection()

func exit_turret_editing_mode():
	if not is_turret_editing_mode:
		return
	
	is_turret_editing_mode = false
	
	if current_editing_turret:
		current_editing_turret.unlock_turret_rotation()
	
	Input.set_custom_mouse_cursor(null)
	
	if editor and editor.is_recycle_mode:
		Input.set_custom_mouse_cursor(editor.saw_cursor)
	
	turret_snap_config = {}
	available_turret_connectors.clear()
	available_block_connectors.clear()
	
	if current_ghost_block:
		current_ghost_block.visible = true
	
	current_editing_turret = null

		
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
	get_tree().current_scene.add_child(current_ghost_block)
	current_ghost_block.modulate = Color(1, 1, 1, 0.5)
	current_ghost_block.z_index = 1000
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
	# 禁用所有碰撞形状
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
	
	# 旋转后重新计算吸附
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_turret_editing_snap_system(global_mouse_pos)

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
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	update_turret_editing_snap_system(global_mouse_pos)

func update_turret_editing_snap_system(mouse_position: Vector2):
	if not is_turret_editing_mode or not current_ghost_block or not current_editing_turret:
		set_ghost_free_position(mouse_position)
		return
	
	# 检查鼠标是否离炮塔太远
	if is_mouse_too_far_from_turret(mouse_position):
		turret_snap_config = {}
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = editor.GHOST_FREE_COLOR
		return
	
	# 重置吸附配置
	turret_snap_config = {}
	
	# 同时获取炮塔内吸附和炮塔外吸附的配置
	var turret_snap = try_turret_internal_snap(mouse_position)
	var external_snap = try_turret_external_snap(mouse_position)
	
	# 计算两种吸附与鼠标的距离
	var turret_snap_distance = INF
	var external_snap_distance = INF
	
	if turret_snap and not turret_snap.is_empty():
		turret_snap_distance = mouse_position.distance_to(turret_snap.ghost_position)
	
	if external_snap and not external_snap.is_empty():
		external_snap_distance = mouse_position.distance_to(external_snap.ghost_position)
	
	# 选择距离最近的吸附，距离相同时优先选择炮塔内吸附
	if turret_snap_distance < external_snap_distance:
		turret_snap_config = turret_snap
	elif external_snap_distance < INF:
		turret_snap_config = external_snap
	else:
		turret_snap_config = {}
	
	# 应用吸附配置
	if turret_snap_config and not turret_snap_config.is_empty():
		current_ghost_block.global_position = turret_snap_config.ghost_position
		if turret_snap_config.has("ghost_rotation"):
			current_ghost_block.global_rotation = turret_snap_config.ghost_rotation
		current_ghost_block.modulate = editor.GHOST_SNAP_COLOR
	else:
		# 都不能吸附，显示为不能放置
		turret_snap_config = {}
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = editor.GHOST_FREE_COLOR

func try_turret_internal_snap(mouse_position: Vector2) -> Dictionary:
	# 尝试炮塔内吸附（与炮塔篮筐的连接点吸附）
	var available_turret_points = get_turret_platform_connectors()
	var available_ghost_points = get_ghost_block_rigidbody_connectors()
	
	if available_turret_points.is_empty() or available_ghost_points.is_empty():
		return {}
	
	# 使用新的吸附逻辑
	var best_snap = find_valid_rigidbody_snap(mouse_position, available_turret_points, available_ghost_points)
	
	if best_snap and not best_snap.is_empty():
		# 添加吸附类型标识
		best_snap["snap_type"] = "internal"
		return best_snap
	
	return {}

func try_turret_external_snap(mouse_position: Vector2) -> Dictionary:
	# 尝试炮塔外吸附（与炮塔上已有方块的连接点吸附）
	var available_block_points = get_turret_block_connection_points()
	var available_ghost_points = get_ghost_block_connection_points()
	
	if available_block_points.is_empty():
		return {}
	
	if available_ghost_points.is_empty():
		return {}
	
	# 使用新的吸附逻辑
	var best_snap = find_valid_regular_snap(mouse_position, available_block_points, available_ghost_points)
	
	if best_snap and not best_snap.is_empty():
		# 添加吸附类型标识
		best_snap["snap_type"] = "external"
		return best_snap
	
	return {}

# === 新的吸附检测函数 ===
func find_valid_rigidbody_snap(mouse_position: Vector2, turret_points: Array[TurretConnector], ghost_points: Array[TurretConnector]) -> Dictionary:
	var best_config = {}
	var min_mouse_distance = INF
	var SNAP_DISTANCE = 64.0  # 吸附距离阈值
	
	for turret_point in turret_points:
		var turret_global_pos = turret_point.global_position
		
		for ghost_point in ghost_points:
			if not can_rigidbody_connectors_connect(turret_point, ghost_point):
				continue
			
			var ghost_global_pos = ghost_point.global_position
			var connector_distance = turret_global_pos.distance_to(ghost_global_pos)
			
			if connector_distance > SNAP_DISTANCE:
				continue
			
			# 计算吸附配置
			var snap_config = calculate_rigidbody_snap_config(turret_point, ghost_point)
			if snap_config.is_empty():
				continue
			
			# 检查网格位置是否可用
			var grid_positions = snap_config.get("grid_positions", [])
			if not are_turret_grid_positions_available(grid_positions, current_editing_turret):
				continue
			
			var snap_position = snap_config.get("ghost_position", Vector2.ZERO)
			var mouse_distance = mouse_position.distance_to(snap_position)
			if mouse_distance < min_mouse_distance:
				min_mouse_distance = mouse_distance
				best_config = snap_config
	
	if best_config and not best_config.is_empty():
		best_config["mouse_distance"] = min_mouse_distance
	
	return best_config

func find_valid_regular_snap(mouse_position: Vector2, block_points: Array[Connector], ghost_points: Array[Connector]) -> Dictionary:
	var best_config = {}
	var min_mouse_distance = INF
	var SNAP_DISTANCE = 64.0  # 吸附距离阈值
	
	for block_point in block_points:
		var block = block_point.find_parent_block()
		if not block or block == current_editing_turret:
			continue
		
		var block_point_global = get_turret_connection_point_global_position(block_point, block)
		
		for ghost_point in ghost_points:
			# 检查连接点类型是否匹配
			if block_point.connection_type != ghost_point.connection_type:
				continue
			
			# 检查连接点方向（使用炮塔系统的角度判断方式）
			if not can_points_connect_with_rotation_for_turret(block_point, ghost_point, 0):
				continue
			
			var ghost_global_pos = ghost_point.global_position
			var connector_distance = block_point_global.distance_to(ghost_global_pos)
			
			if connector_distance > SNAP_DISTANCE:
				continue
			
			# 计算完整的吸附配置（使用与车体系统完全一致的逻辑）
			var target_rotation = calculate_aligned_rotation_for_turret_block(block)
			
			# 使用与车体系统完全一致的网格计算
			var positions = calculate_rotated_grid_positions_turret(block_point, ghost_point)
			
			if positions is bool or positions.is_empty():
				continue
			
			# 检查网格位置是否可用
			if not are_turret_grid_positions_available(positions, current_editing_turret):
				continue
				
			var ghost_local_offset = ghost_point.position.rotated(target_rotation)
			var ghost_position = block_point_global - ghost_local_offset
			
			# 计算鼠标到吸附位置的距离
			var mouse_distance = mouse_position.distance_to(ghost_position)
			
			if mouse_distance < min_mouse_distance:
				min_mouse_distance = mouse_distance
				
				best_config = {
					"vehicle_point": block_point,
					"ghost_point": ghost_point,
					"ghost_position": ghost_position,
					"ghost_rotation": target_rotation,
					"vehicle_block": block,
					"grid_positions": positions
				}
	
	if best_config and not best_config.is_empty():
		best_config["mouse_distance"] = min_mouse_distance
	return best_config

# === 删除模式功能 ===
func try_remove_turret_block():
	if not is_turret_editing_mode or not current_editing_turret:
		return
		
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	var block_to_remove = get_turret_block_at_position(global_mouse_pos)
	
	if block_to_remove and block_to_remove != current_editing_turret:
		current_editing_turret.remove_block_from_turret(block_to_remove)

func get_turret_block_at_position(position: Vector2) -> Block:
	var space_state = get_tree().root.get_world_2d().direct_space_state
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
	if not is_turret_editing_mode:
		return
	
	if not current_editing_turret:
		return
	
	if not current_block_scene:
		return
	
	if not turret_snap_config or turret_snap_config.is_empty():
		return
	
	if not turret_snap_config.has("ghost_position"):
		return
	
	# 使用详细验证
	if not validate_snap_config_before_placement():
		return
	
	var grid_positions = turret_snap_config.get("grid_positions", [])
	
	if not grid_positions or grid_positions.is_empty():
		return
	
	# 创建新块
	var new_block: Block = current_block_scene.instantiate()
	
	if new_block is CollisionObject2D:
		new_block.set_layer(2)
		new_block.collision_mask = 2
	
	new_block.global_position = turret_snap_config.ghost_position
	if turret_snap_config.has("ghost_rotation"):
		new_block.global_rotation = turret_snap_config.ghost_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	
	# 添加到炮塔
	var success = false
	if not grid_positions.is_empty():
		success = current_editing_turret.add_block_to_turret(new_block, grid_positions)
	else:
		# 如果没有网格位置，使用简化方法
		success = current_editing_turret.add_block_to_turret_simple(new_block)
	
	if not success:
		new_block.queue_free()
		return
	#
	## 异步操作
	if new_block.has_method("connect_aready"):
		await new_block.connect_aready()
	else:
		await get_tree().process_frame
	
	
	if selected_vehicle:
		selected_vehicle.update_vehicle()
	
	# 重新开始放置
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
	get_tree().current_scene.add_child(current_ghost_block)
	current_ghost_block.modulate = Color(1, 1, 1, 0.5)
	current_ghost_block.z_index = 1000
	current_ghost_block.do_connect = false
	
	if current_ghost_block is CollisionObject2D:
		current_ghost_block.set_layer(2)
		current_ghost_block.collision_mask = 2
	
	current_ghost_block.base_rotation_degree = base_rotation_degree
	current_ghost_block.rotation = deg_to_rad(base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)
	
	turret_snap_config = {}

# === 放置前验证函数 ===
func validate_snap_config_before_placement() -> bool:
	# 1. 检查吸附配置是否完整
	if not turret_snap_config.has("ghost_position"):
		return false
	
	# 2. 检查网格位置是否仍然可用
	var grid_positions = turret_snap_config.get("grid_positions", [])
	
	if not are_turret_grid_positions_available(grid_positions, current_editing_turret):
		return false
	
	# 3. 检查连接点是否仍然可用
	if turret_snap_config.has("turret_point") and turret_snap_config.has("ghost_point"):
		var turret_point: TurretConnector = turret_snap_config.turret_point
		var ghost_point: TurretConnector = turret_snap_config.ghost_point
		
		if not is_instance_valid(turret_point) or not is_instance_valid(ghost_point):
			return false
		
		if not can_rigidbody_connectors_connect(turret_point, ghost_point):
			return false
		
	elif turret_snap_config.has("vehicle_point") and turret_snap_config.has("ghost_point"):
		var vehicle_point: Connector = turret_snap_config.vehicle_point
		var ghost_point: Connector = turret_snap_config.ghost_point
		
		if not is_instance_valid(vehicle_point) or not is_instance_valid(ghost_point):
			return false
		
		if not can_points_connect_with_rotation_for_turret(vehicle_point, ghost_point, 0):
			return false
	
	# 4. 检查块是否在炮塔范围内
	var ghost_position = turret_snap_config.ghost_position
	
	if is_position_too_far_from_turret(ghost_position):
		return false
	
	return true

func is_position_too_far_from_turret(position: Vector2) -> bool:
	if not current_editing_turret:
		return true
	
	var turret_center = current_editing_turret.global_position
	var distance = position.distance_to(turret_center)
	var turret_radius = calculate_effective_turret_radius()
	
	return distance > turret_radius

# === 炮塔检测功能 ===
func get_turret_at_position(position: Vector2) -> TurretRing:
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 1
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is TurretRing and block.get_parent() == selected_vehicle:
			return block
	return null

# === 炮塔外吸附网格计算函数（与车体系统完全一致）===
func calculate_rotated_grid_positions_turret(turret_point: Connector, ghost_point: Connector):
	# 这个函数与车体编辑系统的 calculate_rotated_grid_positions 完全一致
	var grid_positions = []
	var grid_block = {}
	
	if not current_editing_turret:
		return grid_positions
	
	var block_size = current_ghost_block.size

	var location_v = turret_point.location
	
	var rotation_b = turret_point.find_parent_block().base_rotation_degree
	var grid_b = {}
	var grid_b_pos = {}
	
	for key in current_editing_turret.turret_grid:
		if current_editing_turret.turret_grid[key]["block"]== turret_point.find_parent_block():
			grid_b[key] = current_editing_turret.turret_grid[key]["block"]
	
	grid_b_pos = get_rectangle_corners_turret(grid_b)
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
	grid_connect_g = get_connection_offset_turret(connect_pos_v, turret_point.rotation, turret_point.find_parent_block().base_rotation_degree)
	
	if grid_connect_g != null and block_size != null and ghost_point.location != null:
		grid_block = to_grid_turret(grid_connect_g, block_size, ghost_point.location)
	
	for pos in grid_block:
		if current_editing_turret.turret_grid.has(pos):
			return false
		grid_positions.append(pos)
	
	return grid_positions

func get_connection_offset_turret(connect_pos_v: Vector2i, _rotation: float, direction: int) -> Vector2i:
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

func get_rectangle_corners_turret(grid_data: Dictionary) -> Dictionary:
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

func to_grid_turret(grid_connect_g: Vector2i, block_size: Vector2i, connect_pos_g: Vector2i) -> Dictionary:
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

# === 吸附系统辅助函数 ===
func get_turret_connection_point_global_position(point: Connector, block: Block) -> Vector2:
	return block.global_position + point.position.rotated(block.global_rotation)

func calculate_aligned_rotation_for_turret_block(vehicle_block: Block) -> float:
	var world_rotation = vehicle_block.global_rotation
	var self_rotation = deg_to_rad(vehicle_block.base_rotation_degree)
	var base_rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	return world_rotation + base_rotation - self_rotation

func can_points_connect_with_rotation_for_turret(point_a: Connector, point_b: Connector, ghost_rotation: float) -> bool:
	if point_a.connection_type != point_b.connection_type:
		return false
	
	# 使用炮塔系统的角度差判断方式（保持原有逻辑）
	var ghost_point_direction = wrapf(point_b.global_rotation, -PI, PI)
	var vehicle_point_direction = wrapf(point_a.global_rotation, -PI, PI)
	
	# 计算角度差
	var angle_diff = abs(wrapf(vehicle_point_direction - ghost_point_direction, -PI, PI))
	
	# 允许更大的角度容差，比如150-210度范围内都认为是可连接的
	return angle_diff > deg_to_rad(150) and angle_diff < deg_to_rad(210)

# === 连接点获取函数 ===
func get_turret_platform_connectors() -> Array[TurretConnector]:
	var points: Array[TurretConnector] = []
	
	if not current_editing_turret:
		return points
	
	for body in current_editing_turret.turret_basket.get_children():
		if body is StaticBody2D:
			for connector in body.get_children():
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
		if is_instance_valid(block) and block != current_editing_turret:
			for point in block.connection_points:
				if (point is Connector and 
					point.is_connection_enabled and 
					point.connected_to == null):
					points.append(point)
	
	return points

func get_ghost_block_rigidbody_connectors() -> Array[TurretConnector]:
	var points: Array[TurretConnector] = []
	
	if not current_ghost_block:
		return points
	
	# 确保我们找到的是正确的连接点类型
	for connector in current_ghost_block.find_children("*", "TurretConnector", true):
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
				points.append(point)
	return points

# === 刚性体吸附系统 ===
func calculate_rigidbody_snap_config(turret_point: TurretConnector, ghost_point: TurretConnector) -> Dictionary:
	if not turret_point or not ghost_point or not current_ghost_block or not current_editing_turret:
		return {}
	
	# 计算网格位置
	var grid_positions = calculate_rigidbody_grid_positions(turret_point, ghost_point)
	if not are_turret_grid_positions_available(grid_positions, current_editing_turret):
		return {}
	
	# 计算世界位置和旋转
	var world_position = calculate_turret_world_position(turret_point, ghost_point.position, deg_to_rad(ghost_point.get_parent().base_rotation_degree))
	var target_rotation = calculate_turret_block_rotation(turret_point, ghost_point)
	
	return {
		"turret_point": turret_point,
		"ghost_point": ghost_point,
		"ghost_position": world_position,
		"ghost_rotation": target_rotation,
		"grid_positions": grid_positions,
		"connection_type": "rigidbody"
	}

func calculate_rigidbody_grid_positions(turret_point: TurretConnector, ghost_point: TurretConnector) -> Array:
	var positions = []
	var turret_local_pos = turret_point.location
	var ghost_local_pos = ghost_point.location
	
	# 计算基准位置
	var base_pos = turret_local_pos
	
	# 根据虚影块的旋转计算所有网格位置
	for x in range(current_ghost_block.size.x):
		for y in range(current_ghost_block.size.y):
			var pos = calculate_rigidbody_position(base_pos, Vector2i(x, y), ghost_local_pos, current_ghost_block.base_rotation_degree)
			positions.append(pos)
	
	return positions

func calculate_rigidbody_position(base_pos: Vector2i, local_pos: Vector2i, connector_pos: Vector2i, rotation_degree: int) -> Vector2i:
	# 使用与车体系统一致的旋转计算
	if rotation_degree == 0:
		return Vector2i(base_pos.x - connector_pos.x + local_pos.x, base_pos.y - connector_pos.y + local_pos.y)
	elif rotation_degree == -90:
		return Vector2i(base_pos.x - connector_pos.y + local_pos.y, base_pos.y + connector_pos.x - local_pos.x)
	elif rotation_degree == -180 or rotation_degree == 180:
		return Vector2i(base_pos.x + connector_pos.x - local_pos.x, base_pos.y + connector_pos.y - local_pos.y)
	elif rotation_degree == 90:
		return Vector2i(base_pos.x + connector_pos.y - local_pos.y, base_pos.y - connector_pos.x + local_pos.x)
	else:
		return Vector2i(base_pos.x - connector_pos.x + local_pos.x, base_pos.y - connector_pos.y + local_pos.y)

func calculate_turret_world_position(turret_point: TurretConnector, ghost_local_pos: Vector2, rotation: float) -> Vector2:
	var use_pos = turret_point.position - ghost_local_pos.rotated(rotation)
	return turret_point.get_parent().to_global(use_pos)

func calculate_turret_block_rotation(turret_point: TurretConnector, ghost_point: TurretConnector) -> float:
	var turret_direction = turret_point.get_parent().global_rotation
	var ghost_base_rotation = deg_to_rad(ghost_point.get_parent().base_rotation_degree)
	return turret_direction + ghost_base_rotation

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
	
	var can_connect = a_is_turret != b_is_turret
	
	return can_connect

# === 网格位置验证函数（简化版）===
func are_turret_grid_positions_available(grid_positions: Array, turret: TurretRing) -> bool:
	if not turret:
		return false
	
	for i in range(grid_positions.size()):
		var pos = grid_positions[i]
		if not is_grid_position_available(pos, turret):
			return false
	
	return true

func is_grid_position_available(grid_pos: Vector2i, turret: TurretRing) -> bool:
	if not turret:
		return false
	
	# 检查位置是否在炮塔网格中
	var existing_block = turret.get_turret_block_at_position(grid_pos)
	if existing_block:
		return false
	
	return true

# === 距离检测函数 ===
func is_mouse_too_far_from_turret(mouse_position: Vector2) -> bool:
	if not current_editing_turret:
		return true
	
	var turret_center = current_editing_turret.global_position
	var distance = mouse_position.distance_to(turret_center)
	var effective_radius = calculate_effective_turret_radius()

	return distance > effective_radius

func calculate_effective_turret_radius() -> float:
	if not current_editing_turret:
		return 0.0
	
	# 基础半径基于炮塔大小
	var base_radius = max(current_editing_turret.size.x, current_editing_turret.size.y)
	
	# 考虑已放置块的最大延伸
	var attached_blocks = current_editing_turret.get_attached_blocks()
	var max_extension = 0.0
	
	for block in attached_blocks:
		if is_instance_valid(block):
			var block_distance = block.global_position.distance_to(current_editing_turret.global_position)
			# 加上块本身的大小
			var block_radius = max(block.size.x, block.size.y) * GRID_SIZE * 0.5
			var total_distance = block_distance + block_radius
			max_extension = max(max_extension, total_distance)
	
	# 使用较大的半径，确保外部吸附有足够空间
	var effective_radius = max(base_radius, max_extension) + MAX_SNAP_DISTANCE
	
	return effective_radius

# === 通用函数 ===
func set_ghost_free_position(mouse_position: Vector2):
	current_ghost_block.global_position = mouse_position
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
	current_ghost_block.modulate = editor.GHOST_FREE_COLOR
	turret_snap_config = {}
