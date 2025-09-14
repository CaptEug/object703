class_name VehicleEditor
extends Node

### CONSTANTS ###
const CONNECTION_SNAP_DISTANCE := 50.0  # 吸附距离
const ROTATION_SNAP_ANGLE := 15.0  # 旋转吸附角度(度)

### EDITOR STATE ###
var is_edit_mode := false
var current_vehicle: Vehicle = null
var ghost_block: Block = null
var current_block_scene: PackedScene = null
var available_connection_points: Array[ConnectionPoint] = []
var current_snap_point: ConnectionPoint = null
var ghost_rotation_index := 0
var is_snapping := false

### INVENTORY ###
var inventory := {
	"rusty_track": 10,
	"kwak45": 10,
	"maybach_hl_250": 10,
	"d_52s": 10,
	"zis_57_2": 10,
	"fuel_tank": 10,
	"cupola": 10,
	"ammo_rack": 10,
	"tankbuilder": 10,
	"pike_armor": 10,
	"armor": 10
}

### NODE REFERENCES ###
var ui_instance: Control

#-----------------------------------------------------------------------------#
#                           CORE FUNCTIONS                                    #
#-----------------------------------------------------------------------------#

func _ready():
	# 查找UI实例
	find_ui_instance()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event):
	if event is InputEventKey and event.keycode == KEY_TAB and event.pressed:
		handle_edit_mode_toggle()
	
	if is_edit_mode:
		handle_edit_mode_input(event)

func _process(_delta):
	if is_edit_mode and ghost_block:
		update_ghost_position()
		check_build_validity()

#-----------------------------------------------------------------------------#
#                           EDIT MODE MANAGEMENT                              #
#-----------------------------------------------------------------------------#

func handle_edit_mode_toggle():
	if is_edit_mode:
		exit_edit_mode()
	else:
		try_enter_edit_mode()

func try_enter_edit_mode():
	var vehicle = get_vehicle_under_mouse()
	if vehicle:
		enter_edit_mode(vehicle)
	else:
		print("没有找到可编辑的车辆")

func get_vehicle_under_mouse() -> Vehicle:
	var viewport = get_viewport()
	if not viewport:
		return null
		
	var mouse_pos = viewport.get_mouse_position()
	var space_state = viewport.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = viewport.get_camera_2d().get_global_mouse_position() if viewport.get_camera_2d() else Vector2.ZERO
	query.collision_mask = 1  # 车辆所在的碰撞层
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result = space_state.intersect_point(query)
	
	for collision in result:
		var collider = collision.collider
		if collider is Block:
			var vehicle = collider.get_parent_vehicle()
			if vehicle:
				return vehicle
		elif collider is Vehicle:
			return collider
	
	return null

func enter_edit_mode(vehicle: Vehicle):
	is_edit_mode = true
	current_vehicle = vehicle
	
	# 更新可用连接点
	update_available_connection_points()
	
	# 显示UI
	if ui_instance:
		ui_instance.show()
		ui_instance.setup_inventory(inventory)
		ui_instance.block_selected.connect(_on_block_selected)
	
	# 设置鼠标模式
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	
	print("进入编辑模式: ", vehicle.vehicle_name)

func exit_edit_mode():
	is_edit_mode = false
	
	# 清理ghost block
	if ghost_block and is_instance_valid(ghost_block):
		ghost_block.queue_free()
		ghost_block = null
	
	current_vehicle = null
	available_connection_points.clear()
	current_snap_point = null
	is_snapping = false
	
	# 隐藏UI并断开信号
	if ui_instance:
		ui_instance.hide()
		if ui_instance.block_selected.is_connected(_on_block_selected):
			ui_instance.block_selected.disconnect(_on_block_selected)
	
	# 恢复鼠标模式
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	print("退出编辑模式")

#-----------------------------------------------------------------------------#
#                           CONNECTION POINT MANAGEMENT                       #
#-----------------------------------------------------------------------------#

func update_available_connection_points():
	available_connection_points.clear()
	
	if not current_vehicle or not is_instance_valid(current_vehicle):
		return
	
	# 收集车辆上所有可用的连接点
	for block in current_vehicle.blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if point.is_connection_enabled and not point.is_joint_active():
					available_connection_points.append(point)

func find_nearest_connection_point(mouse_pos: Vector2) -> ConnectionPoint:
	var nearest_point: ConnectionPoint = null
	var min_distance := INF
	print(available_connection_points)
	for point in available_connection_points:
		if not is_instance_valid(point) or point.is_joint_active():
			continue
			
		var distance = point.global_position.distance_to(mouse_pos)
		if distance < min_distance and distance < CONNECTION_SNAP_DISTANCE:
			min_distance = distance
			nearest_point = point
			print(nearest_point)
	return nearest_point

#-----------------------------------------------------------------------------#
#                           GHOST BLOCK MANAGEMENT                            #
#-----------------------------------------------------------------------------#

func _on_block_selected(scene_path: String):
	current_block_scene = load(scene_path)
	if current_block_scene:
		create_ghost_block()

func create_ghost_block():
	# 清理旧的ghost block
	if ghost_block and is_instance_valid(ghost_block):
		ghost_block.queue_free()
	
	if not current_block_scene:
		return
	
	# 创建新的ghost block
	ghost_block = current_block_scene.instantiate()
	if not ghost_block:
		return
	
	# 设置ghost属性
	ghost_block.modulate = Color(1, 1, 1, 0.5)
	ghost_block.collision_layer = 0
	ghost_block.collision_mask = 0
	
	# 禁用碰撞体和物理
	for child in ghost_block.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
		elif child is RigidBody2D:
			child.freeze = true
	
	add_child(ghost_block)
	ghost_rotation_index = 0
	apply_current_rotation()

func apply_current_rotation():
	if not ghost_block or not is_instance_valid(ghost_block):
		return
	
	# 获取当前旋转配置下的连接点
	var ghost_points = ghost_block.get_available_connection_points()
	if ghost_points.is_empty():
		return
	
	# 使用当前旋转索引对应的连接点
	var target_index = ghost_rotation_index % ghost_points.size()
	var target_point = ghost_points[target_index]
	
	# 计算旋转角度
	var target_rotation = target_point.global_rotation - ghost_block.global_rotation
	ghost_block.rotation = target_rotation

func rotate_ghost_block():
	if not ghost_block or not is_instance_valid(ghost_block):
		return
	
	var ghost_points = ghost_block.get_available_connection_points()
	if ghost_points.is_empty():
		return
	
	ghost_rotation_index += 1
	apply_current_rotation()
	
	print("旋转到连接点: ", ghost_rotation_index % ghost_points.size())

#-----------------------------------------------------------------------------#
#                           BUILD PROCESS                                     #
#-----------------------------------------------------------------------------#

func update_ghost_position():
	var viewport = get_viewport()
	if not viewport:
		return
		
	var mouse_pos = viewport.get_camera_2d().get_global_mouse_position() if viewport.get_camera_2d() else Vector2.ZERO
	
	# 寻找最近的连接点
	var new_snap_point = find_nearest_connection_point(mouse_pos)
	
	if new_snap_point and is_instance_valid(new_snap_point):
		# 吸附到连接点
		current_snap_point = new_snap_point
		is_snapping = true
		snap_to_connection_point(current_snap_point)
	else:
		# 自由移动
		current_snap_point = null
		is_snapping = false
		ghost_block.global_position = mouse_pos

func snap_to_connection_point(snap_point: ConnectionPoint):
	if not ghost_block or not is_instance_valid(ghost_block):
		return
	
	# 获取ghost block的当前连接点
	var ghost_points = ghost_block.get_available_connection_points()
	if ghost_points.is_empty():
		return
	
	var target_index = ghost_rotation_index % ghost_points.size()
	var ghost_point = ghost_points[target_index]
	
	if not is_instance_valid(ghost_point):
		return
	
	# 计算位置偏移
	var local_offset = ghost_point.position
	var rotated_offset = local_offset.rotated(ghost_block.rotation)
	ghost_block.global_position = snap_point.global_position - rotated_offset
	
	# 对齐旋转
	ghost_block.global_rotation = snap_point.global_rotation - ghost_point.rotation

func check_build_validity():
	if not ghost_block or not is_instance_valid(ghost_block):
		return
	
	if not is_snapping or not current_snap_point:
		ghost_block.modulate = Color(1, 0.5, 0.5, 0.5)  # 红色，不可建造
		return
	
	# 检查连接点是否匹配
	var ghost_points = ghost_block.get_available_connection_points()
	if ghost_points.is_empty():
		ghost_block.modulate = Color(1, 0.5, 0.5, 0.5)
		return
	
	var target_index = ghost_rotation_index % ghost_points.size()
	var ghost_point = ghost_points[target_index]
	
	if not is_instance_valid(ghost_point):
		ghost_block.modulate = Color(1, 0.5, 0.5, 0.5)
		return
	
	if ghost_point.can_connect_with(current_snap_point):
		ghost_block.modulate = Color(1, 1, 1, 0.5)  # 白色，可建造
	else:
		ghost_block.modulate = Color(1, 0.5, 0.5, 0.5)  # 红色，不可建造

func place_block():
	if not can_place_block():
		print("无法放置方块")
		return
	
	var block_name = ghost_block.scene_file_path.get_file().get_basename()
	if inventory.get(block_name, 0) <= 0:
		print("库存不足: ", block_name)
		return
	
	# 创建实际方块
	var new_block: Block = current_block_scene.instantiate()
	new_block.global_position = ghost_block.global_position
	new_block.global_rotation = ghost_block.global_rotation
	
	# 添加到车辆
	current_vehicle.add_child(new_block)
	# 假设 _add_block 方法需要更多参数，这里需要根据实际情况调整
	# current_vehicle._add_block(new_block, current_snap_point, ghost_point)
	
	# 建立连接
	var ghost_points = ghost_block.get_available_connection_points()
	var target_index = ghost_rotation_index % ghost_points.size()
	var ghost_point = ghost_points[target_index]
	
	if ghost_point and current_snap_point:
		new_block.request_connection(ghost_point, current_snap_point)
	
	# 更新库存
	inventory[block_name] -= 1
	if ui_instance:
		ui_instance.update_inventory_display(inventory)
	
	# 更新可用连接点
	update_available_connection_points()
	
	# 重新创建ghost block
	create_ghost_block()
	
	print("放置方块: ", block_name)

func can_place_block() -> bool:
	return (is_edit_mode and 
			ghost_block and 
			is_instance_valid(ghost_block) and
			is_snapping and
			current_snap_point and
			is_instance_valid(current_snap_point) and
			current_vehicle and
			is_instance_valid(current_vehicle) and
			ghost_block.modulate != Color(1, 0.5, 0.5, 0.5))

#-----------------------------------------------------------------------------#
#                           INPUT HANDLING                                    #
#-----------------------------------------------------------------------------#

func handle_edit_mode_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			place_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			rotate_ghost_block()
	
	elif event is InputEventKey:
		if event.keycode == KEY_ESCAPE and event.pressed:
			exit_edit_mode()
		elif event.keycode == KEY_R and event.pressed:
			rotate_ghost_block()

#-----------------------------------------------------------------------------#
#                           UTILITY FUNCTIONS                                 #
#-----------------------------------------------------------------------------#

func find_ui_instance():
	# 尝试在不同位置查找UI
	var paths_to_try = [
		"../CanvasLayer/Tankbuilderui",
		"../../CanvasLayer/Tankbuilderui",
		"CanvasLayer/Tankbuilderui"
	]
	
	for path in paths_to_try:
		if has_node(path):
			ui_instance = get_node(path)
			break
	
	if not ui_instance:
		push_warning("Tankbuilder UI not found")

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_edit_mode:
			exit_edit_mode()

#-----------------------------------------------------------------------------#
#                           PUBLIC API                                        #
#-----------------------------------------------------------------------------#

func get_current_vehicle() -> Vehicle:
	return current_vehicle

func is_in_edit_mode() -> bool:
	return is_edit_mode

func get_available_blocks() -> Array:
	return inventory.keys()

func add_to_inventory(block_name: String, amount: int = 1):
	inventory[block_name] = inventory.get(block_name, 0) + amount
	if ui_instance:
		ui_instance.update_inventory_display(inventory)
