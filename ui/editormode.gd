extends Control

@onready var tab_container = $TabContainer
@onready var description_label = $Panel/RichTextLabel
@onready var build_vehicle_button = $Panel/SaveButton
@onready var save_dialog = $SaveDialog
@onready var name_input = $Panel/NameInput
@onready var error_label = $SaveDialog/ErrorLabel
@onready var recycle_button = $Panel/DismantleButton

var saw_cursor:Texture = preload("res://assets/icons/saw_cursor.png")

signal block_selected(scene_path: String)
signal vehicle_saved(vehicle_name: String)
signal recycle_mode_toggled(is_recycle_mode: bool)

const BLOCK_PATHS = {
	"Firepower": "res://blocks/firepower/",
	"Mobility": "res://blocks/mobility/",
	"Command": "res://blocks/command/",
	"Building": "res://blocks/building/",
	"Structual": "res://blocks/structual/",
	"Auxiliary": "res://blocks/auxiliary/"
}

var item_lists = {}
var is_recycle_mode := false

# === 编辑器模式变量 ===
var is_editing := false
var selected_vehicle: Vehicle = null
var current_ghost_block: Node2D = null
var current_block_scene: PackedScene = null
var panel_instance: Control = null
var camera:Camera2D

# 连接点吸附系统
var current_ghost_connection_index := 0
var current_vehicle_connection_index := 0
var available_ghost_points: Array[ConnectionPoint] = []
var available_vehicle_points: Array[ConnectionPoint] = []
var current_snap_config: Dictionary = {}
var base_ghost_rotation := 0.0 
var snap_config

# 存储原始连接状态
var original_connections: Dictionary = {}

func _ready():
	camera = get_tree().current_scene.find_child("Camera2D") as Camera2D
	build_vehicle_button.pressed.connect(_on_build_vehicle_pressed)
	save_dialog.get_ok_button().pressed.connect(_on_save_confirmed)
	save_dialog.close_requested.connect(_on_save_canceled)
	name_input.text_changed.connect(_on_name_input_changed)
	recycle_button.pressed.connect(_on_recycle_button_pressed)
	create_tabs()
	
	save_dialog.hide()
	error_label.hide()
	
	var connect_result = vehicle_saved.connect(_on_vehicle_saved)
	if connect_result == OK:
		print("✅ vehicle_saved 信号连接成功")
	else:
		print("❌ vehicle_saved 信号连接失败，错误代码:", connect_result)
		# 检查连接状态
		if vehicle_saved.is_connected(_on_vehicle_saved):
			print("⚠️  信号已经连接")
		else:
			print("⚠️  信号未连接")
	
	update_recycle_button()
	load_all_blocks()
	
	call_deferred("initialize_editor")

func _input(event):
	# 全局TAB键检测
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		if is_editing:
			exit_editor_mode()
		else:
			if selected_vehicle == null:
				find_and_select_vehicle()
			if selected_vehicle:
				enter_editor_mode(selected_vehicle)
			else:
				print("错误: 未找到可编辑的车辆")
		return
	
	if not is_editing:
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				cancel_placement()
			KEY_R:
				rotate_ghost_connection()  # 旋转幽灵块90度
			KEY_T:
				switch_vehicle_connection()  # 切换车辆连接点
			KEY_F:
				print_connection_points_info()
	
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if is_recycle_mode:
				try_remove_block()
			else:
				try_place_block()


func _process(delta):
	if is_editing and selected_vehicle:
		camera.sync_rotation_to_vehicle(selected_vehicle)
		
	if not is_editing or not current_ghost_block or not selected_vehicle:
		return
		
	if Engine.get_frames_drawn() % 2 == 0:
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		update_ghost_block_position(global_mouse_pos)

# === UI 相关函数 ===
func create_tabs():
	for child in tab_container.get_children():
		child.queue_free()
	
	create_tab_with_itemlist("All")
	
	for category in BLOCK_PATHS:
		create_tab_with_itemlist(category)
	
	for tab_name in item_lists:
		item_lists[tab_name].item_selected.connect(_on_item_selected.bind(tab_name))

func create_tab_with_itemlist(tab_name: String):
	var item_list = ItemList.new()
	item_list.name = tab_name
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.max_columns = 0
	item_list.icon_mode = ItemList.ICON_MODE_TOP
	item_list.fixed_column_width = 100
	item_list.fixed_icon_size = Vector2(64, 64)
	item_list.allow_reselect = false
	item_list.allow_search = false
	
	tab_container.add_child(item_list)
	item_lists[tab_name] = item_list

func load_all_blocks():
	var all_blocks = []
	var categorized_blocks = {}
	
	for category in BLOCK_PATHS:
		categorized_blocks[category] = []
		var dir = DirAccess.open(BLOCK_PATHS[category])
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".tscn"):
					var scene_path = BLOCK_PATHS[category] + file_name
					var scene = load(scene_path)
					var block = scene.instantiate()
					if block is Block:
						all_blocks.append({
							"name": block.block_name,
							"icon": block.get_icon_texture(),
							"path": scene_path
						})
						categorized_blocks[category].append({
							"name": block.block_name,
							"icon": block.get_icon_texture(),
							"path": scene_path
						})
						block.queue_free()
				file_name = dir.get_next()
	
	populate_item_list(item_lists["All"], all_blocks)
	for category in categorized_blocks:
		if item_lists.has(category):
			populate_item_list(item_lists[category], categorized_blocks[category])

func populate_item_list(item_list: ItemList, items: Array):
	for item in items:
		var idx = item_list.add_item(item.name)
		item_list.set_item_icon(idx, item.icon)
		item_list.set_item_metadata(idx, item.path)

func _on_item_selected(index: int, tab_name: String):
	var item_list = item_lists[tab_name]
	var scene_path = item_list.get_item_metadata(index)
	if scene_path:
		emit_signal("block_selected", scene_path)
		update_description(scene_path)
		if is_editing:
			start_block_placement(scene_path)

func update_description(scene_path: String):
	var scene = load(scene_path)
	var block = scene.instantiate()
	if block:
		description_label.clear()
		description_label.append_text("[b]%s[/b]\n\n" % block.block_name)
		description_label.append_text("TYPE: %s\n" % block.type)
		description_label.append_text("SIZE: %s\n" % str(block.size))
		if block.has_method("get_description"):
			description_label.append_text("DESCRIPTION: %s\n" % block.get_description())
		block.queue_free()

func _on_build_vehicle_pressed():
	print("=== 保存按钮被点击 ===")
	print("当前选中的车辆: ", selected_vehicle)
	print("编辑模式状态: ", is_editing)
	show_save_dialog()

func show_save_dialog():
	error_label.text = ""
	var vehicle_name = name_input.text.strip_edges()
	if vehicle_name.is_empty():
		error_label.text = "Name cannot be empty!"
		error_label.show()
	elif vehicle_name.contains("/") or vehicle_name.contains("\\"):
		error_label.text = "The name cannot contain special characters!"
		error_label.show()
	else:
		save_dialog.title = "Make sure?"
		error_label.text = vehicle_name
		error_label.show()
	save_dialog.popup_centered()

func _on_save_confirmed():
	var vehicle_name = name_input.text.strip_edges()
	
	if vehicle_name.is_empty():
		return
	
	if vehicle_name.contains("/") or vehicle_name.contains("\\"):
		return
	
	save_vehicle(vehicle_name)
	save_dialog.hide()


func _on_save_canceled():
	save_dialog.hide()

func _on_name_input_changed(_new_text: String):
	error_label.hide()

func _on_recycle_button_pressed():
	is_recycle_mode = !is_recycle_mode
	update_recycle_button()
	emit_signal("recycle_mode_toggled", is_recycle_mode)

func update_recycle_button():
	if is_recycle_mode:
		recycle_button.add_theme_color_override("font_color", Color.RED)
	else:
		recycle_button.remove_theme_color_override("font_color")

func reload_blocks():
	for item_list in item_lists.values():
		item_list.clear()
	load_all_blocks()
	print("方块列表已重新加载")

# === 编辑器模式功能 ===
func initialize_editor():
	print("正在初始化编辑器...")
	
	var testground = get_tree().current_scene
	if testground:
		var canvas_layer = testground.find_child("CanvasLayer", false, false)
		if canvas_layer:
			var panels = canvas_layer.get_children()
			for item in panels:
				if item is FloatingPanel and item.selected_vehicle != null:
					panel_instance = item
					break
	
	print("编辑器初始化完成")

func find_and_select_vehicle():
	var testground = get_tree().current_scene
	if testground:
		var canvas_layer = testground.find_child("CanvasLayer", false, false)
		if canvas_layer:
			var panels = canvas_layer.get_children()
			for item in range(panels.size() - 1, -1, -1):
				if panels[item] is FloatingPanel and panels[item].selected_vehicle != null:
					panel_instance = panels[item]
					break
	if testground and panel_instance:
		if panel_instance.selected_vehicle:
			selected_vehicle = panel_instance.selected_vehicle
			name_input.text = selected_vehicle.vehicle_name
			print("找到车辆: ", selected_vehicle.vehicle_name)
			return

func enter_editor_mode(vehicle: Vehicle):
	if is_editing:
		exit_editor_mode()
	selected_vehicle = vehicle

	is_editing = true
	
	camera.focus_on_vehicle(selected_vehicle)
	camera.sync_rotation_to_vehicle(selected_vehicle)
	
	print("=== 进入编辑模式 ===")
	
	save_original_connections()
	enable_all_connection_points_for_editing()
	
	vehicle.control = Callable()
	show()
	
	# 重置连接点索引
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0
	
	print("=== 编辑模式就绪 ===")

func exit_editor_mode():
	if not is_editing:
		return
	
	print("=== 退出编辑模式 ===")
	
	restore_original_connections()
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	camera.target_rot = 0.0
	print("yes")
	
	hide()
	is_editing = false
	selected_vehicle = null
	print("=== 编辑模式已退出 ===")

func save_original_connections():
	original_connections.clear()
	
	if not selected_vehicle:
		return
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point) and point.connected_to:
					var connection_key = get_connection_key(point, point.connected_to)
					original_connections[connection_key] = {
						"from_point": point,
						"to_point": point.connected_to,
						"from_block": block,
						"to_block": point.connected_to.find_parent_block()
					}

func get_connection_key(point_a: ConnectionPoint, point_b: ConnectionPoint) -> String:
	var block_a = point_a.find_parent_block()
	var block_b = point_b.find_parent_block()
	
	if not block_a or not block_b:
		return ""
	
	var paths = [str(block_a.get_path()) + ":" + point_a.name, str(block_b.get_path()) + ":" + point_b.name]
	paths.sort()
	return paths[0] + "<->" + paths[1]

func enable_all_connection_points_for_editing():
	if not selected_vehicle:
		return
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point):
					point.set_connection_enabled(true)

func restore_original_connections():
	if not selected_vehicle:
		return
	
	enable_all_connection_points_for_editing()
	await get_tree().process_frame
	
	var restored_count = 0
	for connection_key in original_connections:
		var connection = original_connections[connection_key]
		
		if (is_instance_valid(connection.from_point) and 
			is_instance_valid(connection.to_point) and
			is_instance_valid(connection.from_block) and
			is_instance_valid(connection.to_block)):
			
			if (connection.from_point.is_connection_enabled and 
				connection.to_point.is_connection_enabled and
				not connection.from_point.connected_to and
				not connection.to_point.connected_to):
				
				if connection.from_point.can_connect_with(connection.to_point):
					connection.from_point.request_connection(connection.from_point, connection.to_point)
					restored_count += 1
	
	print("成功恢复 ", restored_count, " 个连接")

func start_block_placement(scene_path: String):
	if not is_editing or not selected_vehicle:
		return
	
	print("开始放置块: ", scene_path.get_file())
	
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
	
	# 重置基础旋转角度
	base_ghost_rotation = 0
	current_ghost_block.rotation = base_ghost_rotation
	
	setup_ghost_block_collision(current_ghost_block)
	
	# 重置连接点索引
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0
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

# === 新的连接点吸附系统 ===
func update_ghost_block_position(mouse_position: Vector2):
	# 获取附近的车辆连接点
	available_vehicle_points = selected_vehicle.get_available_points_near_position(mouse_position, 20.0)
	available_ghost_points = get_ghost_block_available_connection_points()
	
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		# 没有可用连接点，自由移动
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = base_ghost_rotation + camera.target_rot# 使用基础旋转
		current_ghost_block.modulate = Color(1, 0.3, 0.3, 0.5)
		current_snap_config = {}
		return
	
	# 获取当前连接配置
	snap_config = get_current_snap_config()
	
	if snap_config:
		
		# 应用吸附位置和自动对齐的旋转
		current_ghost_block.global_position = snap_config.ghost_position
		current_ghost_block.global_rotation = snap_config.ghost_rotation
		current_ghost_block.modulate = Color(0.5, 1, 0.5, 0.5)
		current_snap_config = snap_config
	else:
		# 自由移动
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = base_ghost_rotation  # 使用基础旋转
		current_ghost_block.modulate = Color(1, 0.3, 0.3, 0.5)
		current_snap_config = {}

func get_ghost_block_available_connection_points() -> Array[ConnectionPoint]:
	var points: Array[ConnectionPoint] = []
	if current_ghost_block:
		var connection_points = current_ghost_block.get_available_connection_points()
		for point in connection_points:
			if point is ConnectionPoint:
				point.qeck = false
				points.append(point)
	return points

func get_current_snap_config() -> Dictionary:
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		return {}
	# 寻找最佳匹配的连接点（基于基础旋转来寻找合适的对齐）
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
			# 基于基础旋转计算最佳对齐角度
			var target_rotation = calculate_aligned_rotation_from_base(vehicle_block, vehicle_point, ghost_point)
			# 检查连接点是否可以连接
			if not can_points_connect_with_rotation(vehicle_point, ghost_point, target_rotation):
				continue
				
			var positions = calculate_rotated_grid_positions(vehicle_point, ghost_point, target_rotation)
			if positions is bool:
				continue
			# 计算幽灵块的位置
			var ghost_local_offset = ghost_point.position.rotated(target_rotation)
			var ghost_position = vehicle_point_global - ghost_local_offset
			# 计算鼠标位置与连接点的距离
			var mouse_pos = get_viewport().get_mouse_position()
			var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
			var distance = global_mouse_pos.distance_to(ghost_position)
			# 选择距离鼠标最近的点
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
					"positions":positions
				}
	
	return best_config

func calculate_aligned_rotation_from_base(vehicle_block: Block, vehicle_point: ConnectionPoint, ghost_point: ConnectionPoint) -> float:
	var dir = vehicle_block.rotation_to_parent
	var dir_to_rad = 0
	if dir == "up":
		dir_to_rad = 0
	elif dir == "right":
		dir_to_rad = -PI/2
	elif dir == "left":
		dir_to_rad = PI/2
	else:
		dir_to_rad = PI
	return base_ghost_rotation + dir_to_rad + vehicle_block.global_rotation

func calculate_aligned_direction_from_base(vehicle_block: Block, vehicle_point: ConnectionPoint, ghost_point: ConnectionPoint) -> float:
	# 计算相对于基础旋转的对齐角度
	var result_rotation = 0.0
	# 计算连接点之间的角度差异
	var angle_diff = fmod(vehicle_block.global_rotation + PI, PI * 2) - PI - base_ghost_rotation
	angle_diff = normalize_rotation_simple(angle_diff)	
	if angle_diff >= 0:
		if PI/2 - angle_diff >= angle_diff:
			result_rotation = base_ghost_rotation + angle_diff
		else:
			result_rotation = base_ghost_rotation - (PI/2 - abs(angle_diff))	
		
	return result_rotation

func normalize_rotation_simple(angle: float) -> float:
	var normalized = wrapf(angle, 0, PI/2)
	return normalized

func can_points_connect_with_rotation(point_a: ConnectionPoint, point_b: ConnectionPoint, ghost_rotation: float) -> bool:
	# 检查连接点类型是否匹配
	if point_a.connection_type != point_b.connection_type:
		return false
	# 检查连接点是否启用
	if not point_a.is_connection_enabled or not point_b.is_connection_enabled:
		return false
	# 计算幽灵块连接点在指定旋转下的全局方向
	var ghost_point_direction = point_b.rotation + ghost_rotation
	var angle_diff = are_rotations_opposite_best(ghost_point_direction, point_a.global_rotation, 0.5)
	return angle_diff   # 允许稍大的误差，因为是基于基础旋转的对齐

func are_rotations_opposite_best(rot1: float, rot2: float, tolerance: float = 0.1) -> bool:
	"""
	最可靠的相对角度检测
	"""
	# 使用向量点积的方法来检测方向相对性
	var dir1 = Vector2(cos(rot1), sin(rot1))
	var dir2 = Vector2(cos(rot2), sin(rot2))
	
	# 如果两个方向相反，点积应该接近-1
	var dot_product = dir1.dot(dir2)
	return dot_product < -0.9  # 对应约±25度的误差范围

func get_connection_point_global_position(point: ConnectionPoint, block: Block) -> Vector2:
	return block.global_position + point.position.rotated(block.global_rotation)

func rotate_ghost_connection():
	if not current_ghost_block:
		return
	
	# 旋转基础旋转90度
	base_ghost_rotation += PI / 2
	base_ghost_rotation = fmod(base_ghost_rotation + PI, PI * 2) - PI
	
	# 更新幽灵方块显示（使用基础旋转）
	current_ghost_block.rotation = base_ghost_rotation
	
	# 更新位置
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_ghost_block_position(global_mouse_pos)
	
	print("基础旋转调整到: ", rad_to_deg(base_ghost_rotation), " 度")

func switch_vehicle_connection():
	if available_vehicle_points.is_empty():
		return
	
	# 切换到下一个车辆连接点
	current_vehicle_connection_index = (current_vehicle_connection_index + 1) % available_vehicle_points.size()
	print("切换到车辆连接点: ", current_vehicle_connection_index)
	
	# 更新位置
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_ghost_block_position(global_mouse_pos)

func can_points_connect(point_a: ConnectionPoint, point_b: ConnectionPoint) -> bool:
	# 检查连接点类型是否匹配
	if point_a.connection_type != point_b.connection_type:
		return false
	
	# 检查连接点是否启用
	if not point_a.is_connection_enabled or not point_b.is_connection_enabled:
		return false
	
	# 检查连接点方向是否相对（相差约180度）
	var angle_diff = abs(fmod(point_a.global_rotation - point_b.global_rotation + PI, PI * 2) - PI)
	return angle_diff < 0.1  # 允许小的误差

func calculate_aligned_rotation(vehicle_block: Block, vehicle_point: ConnectionPoint, ghost_point: ConnectionPoint) -> float:
	# 计算基础旋转角度（使连接点方向相对）
	var base_rotation = vehicle_block.global_rotation + vehicle_point.rotation - ghost_point.rotation + PI
	
	# 对齐到最近的90度倍数（0, 90, 180, 270度）
	var degrees = rad_to_deg(base_rotation)
	var aligned_degrees = round(degrees / 90) * 90
	return deg_to_rad(aligned_degrees)

func try_place_block():
	if not current_ghost_block or not selected_vehicle:
		print("无法放置: 没有选择块或车辆")
		return
	
	if not current_snap_config:
		print("错误: 必须靠近连接点放置")
		return
	
	var block_name = current_ghost_block.scene_file_path.get_file().get_basename()
	print("放置块: ", block_name, " 使用连接点配置")
	
	# 断开可能冲突的连接
	var connections_to_disconnect = find_connections_to_disconnect_for_placement()
	disconnect_connections(connections_to_disconnect)
	
	var grid_positions = snap_config.positions
	# 创建新块
	var new_block:Block = current_block_scene.instantiate()
	selected_vehicle.add_child(new_block)
	new_block.global_position = current_snap_config.ghost_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.caculate_direction_to_parent(base_ghost_rotation)
	var control = selected_vehicle.control
	# 计算网格位置并更新
	selected_vehicle._add_block(new_block, new_block.position, grid_positions)
	
	selected_vehicle.control = control
	
	# 继续放置同一类型的块（保持当前基础旋转）
	start_block_placement_with_rotation(current_block_scene.resource_path, base_ghost_rotation)

func start_block_placement_with_rotation(scene_path: String, rotation: float):
	if not is_editing or not selected_vehicle:
		return
	
	print("开始放置块: ", scene_path.get_file(), " 基础旋转: ", rad_to_deg(rotation), " 度")
	
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
	
	# 保持之前的基础旋转
	base_ghost_rotation = rotation
	current_ghost_block.rotation = base_ghost_rotation
	
	setup_ghost_block_collision(current_ghost_block)
	
	# 重置连接点索引
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0
	current_snap_config = {}

func establish_connection(vehicle_point: ConnectionPoint, new_block: Block, ghost_point: ConnectionPoint):
	# 在新块中查找对应的连接点
	var new_block_points = new_block.find_children("*", "ConnectionPoint")
	var target_point = null
	
	for point in new_block_points:
		if point is ConnectionPoint and point.name == ghost_point.name:
			target_point = point
			break
	
	if target_point is ConnectionPoint:
		target_point.is_connection_enabled = true
		vehicle_point.try_connect(target_point)
		print("连接建立: ", vehicle_point.name, " -> ", target_point.name)
	else:
		print("警告: 无法建立连接")

func calculate_rotated_grid_positions(vehiclepoint, ghostpoint, target_rotation):
	var grid_positions = []
	var grid_block = {}
	
	if not selected_vehicle:
		return grid_positions
	
	var block_size = current_ghost_block.size
	
	var location_g = ghostpoint.location
	var location_v = vehiclepoint.location
	
	var rotation_b = round(vehiclepoint.find_parent_block().rotation)
	var grid_b = {}
	var grid_b_pos = {}
	
	for key in selected_vehicle.grid:
		if selected_vehicle.grid[key] == vehiclepoint.find_parent_block():
			grid_b[key] = selected_vehicle.grid[key]
	
	grid_b_pos = get_rectangle_corners(grid_b)
	var grid_connect_g
	if grid_b_pos.is_empty():
		return false
	# 提取重复的连接点计算逻辑
	if rotation_b == 0:
		var connect_pos_v = Vector2i(grid_b_pos["1"].x + location_v.x, grid_b_pos["1"].y + location_v.y)
		grid_connect_g = get_connection_offset(connect_pos_v, vehiclepoint.rotation, vehiclepoint.find_parent_block().rotation_to_parent)
	elif rotation_b == -2:
		var connect_pos_v = Vector2i(grid_b_pos["4"].x + location_v.y, grid_b_pos["4"].y - location_v.x)
		grid_connect_g = get_connection_offset(connect_pos_v, vehiclepoint.rotation, vehiclepoint.find_parent_block().rotation_to_parent)
	elif rotation_b == -3:
		var connect_pos_v = Vector2i(grid_b_pos["3"].x - location_v.x, grid_b_pos["3"].y - location_v.y)
		grid_connect_g = get_connection_offset(connect_pos_v, vehiclepoint.rotation, vehiclepoint.find_parent_block().rotation_to_parent)
	elif rotation_b == 2:
		var connect_pos_v = Vector2i(grid_b_pos["2"].x - location_v.y, grid_b_pos["2"].y + location_v.x)
		grid_connect_g = get_connection_offset(connect_pos_v, vehiclepoint.rotation, vehiclepoint.find_parent_block().rotation_to_parent)
	
	if grid_connect_g != null and block_size != null and ghostpoint.location != null:
		grid_block = to_grid(grid_connect_g, block_size, ghostpoint.location, target_rotation)
	
	for pos in grid_block:
		if selected_vehicle.grid.has(pos):
			return false
		grid_positions.append(pos)
	
	return grid_positions

# 提取的重复逻辑函数
func get_connection_offset(connect_pos_v: Vector2i, rotation: float, direction: String) -> Vector2i:
	var rounded_rotation_or = rotation
	var rounded_rotation = 0
	if direction == "up":
		rounded_rotation = rounded_rotation_or
	elif direction == "left":
		rounded_rotation = rounded_rotation_or - PI/2
	elif direction == "right":
		rounded_rotation = rounded_rotation_or + PI/2
	elif direction == "down":
		rounded_rotation = rounded_rotation_or + PI
	
	rounded_rotation = round(wrapf(rounded_rotation, -PI, PI))
	
	if rounded_rotation == 0:
		return Vector2i(connect_pos_v.x + 1, connect_pos_v.y)
	elif rounded_rotation == -2:
		return Vector2i(connect_pos_v.x, connect_pos_v.y - 1)
	elif rounded_rotation == -3 or rounded_rotation == 3:
		return Vector2i(connect_pos_v.x - 1, connect_pos_v.y)
	elif rounded_rotation == 2:
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

func to_grid(grid_connect_g: Vector2i, block_size: Vector2i, connect_pos_g: Vector2i, target_rotaion: float) -> Dictionary:
	var grid_block = {}
	var current_xd_rotaion = selected_vehicle
	for i in block_size.x:
		for j in block_size.y:
			if round(base_ghost_rotation) == 0:
				var left_up = Vector2i(grid_connect_g.x - connect_pos_g.x, grid_connect_g.y - connect_pos_g.y)
				grid_block[Vector2i(left_up.x + i, left_up.y + j)] = current_ghost_block
			elif round(base_ghost_rotation) == -2:
				var left_up = Vector2i(grid_connect_g.x - connect_pos_g.y, grid_connect_g.y + connect_pos_g.x)
				grid_block[Vector2i(left_up.x + j, left_up.y - i)] = current_ghost_block
			elif round(base_ghost_rotation) == -3:
				var left_up = Vector2i(grid_connect_g.x + connect_pos_g.x, grid_connect_g.y + connect_pos_g.y)
				grid_block[Vector2i(left_up.x - i, left_up.y - j)] = current_ghost_block
			elif round(base_ghost_rotation) == 2:
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
			if block is Command:
				print("不能移除命令块")
				continue
			
			var block_name = block.block_name
			var connections_to_disconnect = find_connections_for_block(block)
			disconnect_connections(connections_to_disconnect)
			
			selected_vehicle.remove_block(block)
			enable_connection_points_for_blocks(get_affected_blocks_for_removal(block))
			call_deferred("check_vehicle_stability")
			print("移除块: ", block_name)
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
	print("放置已取消")

func get_block_size(block: Block) -> Vector2i:
	if block.has_method("get_size"):
		return block.size
	return Vector2i(1, 1)

func check_vehicle_stability():
	if not selected_vehicle:
		return
	
	var checked_blocks = {}
	var command_blocks = []
	
	for block in selected_vehicle.blocks:
		if block is Command:
			command_blocks.append(block)
	
	if command_blocks.is_empty():
		print("警告: 车辆没有命令块！")
		return
	
	for command_block in command_blocks:
		check_connections_from_block(command_block, checked_blocks)
	
	for block in selected_vehicle.blocks:
		if not checked_blocks.get(block, false) and not block is Command:
			print("警告: 块 ", block.block_name, " 未连接到命令块！")

func check_connections_from_block(block: Block, checked_blocks: Dictionary):
	if checked_blocks.get(block, false):
		return
	
	checked_blocks[block] = true
	
	for point in block.connection_points:
		if point.connected_to:
			var connected_block = point.connected_to.find_parent_block()
			if connected_block and not checked_blocks.get(connected_block, false):
				check_connections_from_block(connected_block, checked_blocks)

func print_connection_points_info():
	if not selected_vehicle:
		return
	
	print("=== 连接点信息 ===")
	for block in selected_vehicle.blocks:
		for point in block.connection_points:
			var info = point.name + " - 启用: " + str(point.is_connection_enabled)
			if point.connected_to:
				info += " - 已连接"
			print(info)
	print("=================")

func _on_vehicle_saved(vehicle_name: String):
	save_vehicle(vehicle_name)

func save_vehicle(vehicle_name: String):
	if not selected_vehicle:
		print("错误: 没有选中的车辆")
		return
	
	print("正在保存车辆: ", vehicle_name)
	
	var blueprint_data = create_blueprint_data(vehicle_name)
	var blueprint_path = "res://vehicles/blueprint/%s.json" % vehicle_name
	
	if save_blueprint(blueprint_data, blueprint_path):
		selected_vehicle.vehicle_name = vehicle_name
		selected_vehicle.blueprint = blueprint_data
		print("车辆保存成功: ", blueprint_path)
	else:
		push_error("车辆保存失败")

func create_blueprint_data(vehicle_name: String) -> Dictionary:
	var blueprint_data = {
		"name": vehicle_name,
		"blocks": {},
		"vehicle_size": [0, 0]
	}
	
	var block_counter = 1
	var processed_blocks = {}
	
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	
	for grid_pos in selected_vehicle.grid:
		min_x = min(min_x, grid_pos.x)
		min_y = min(min_y, grid_pos.y)
		max_x = max(max_x, grid_pos.x)
		max_y = max(max_y, grid_pos.y)
	
	for grid_pos in selected_vehicle.grid:
		var block = selected_vehicle.grid[grid_pos]
		if not processed_blocks.has(block):
			var relative_pos = Vector2i(grid_pos.x - min_x, grid_pos.y - min_y)
			var rotation_str = get_rotation_direction(block.global_rotation)
			
			blueprint_data["blocks"][str(block_counter)] = {
				"name": block.block_name,
				"path": block.scene_file_path,
				"base_pos": [relative_pos.x, relative_pos.y],
				"rotation": rotation_str,
			}
			block_counter += 1
			processed_blocks[block] = true
	
	blueprint_data["vehicle_size"] = [max_x - min_x + 1, max_y - min_y + 1]
	return blueprint_data

func get_rotation_direction(angle: float) -> String:
	var normalized = fmod(angle, TAU)
	if abs(normalized) <= PI/4 or abs(normalized) >= 7*PI/4:
		return "up"
	elif normalized >= PI/4 and normalized <= 3*PI/4:
		return "right"
	elif normalized >= 3*PI/4 and normalized <= 5*PI/4:
		return "down"
	else:
		return "left"

func save_blueprint(blueprint_data: Dictionary, save_path: String) -> bool:
	var dir = DirAccess.open("res://vehicles/blueprint/")
	if not dir:
		DirAccess.make_dir_absolute("res://vehicles/blueprint/")
	
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(blueprint_data, "\t"))
		file.close()
		print("车辆蓝图已保存到:", save_path)
		return true
	else:
		push_error("文件保存失败:", FileAccess.get_open_error())
		return false
