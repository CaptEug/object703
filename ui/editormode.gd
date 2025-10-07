extends Control

@onready var tab_container = $TabContainer
@onready var description_label = $Panel/RichTextLabel
@onready var build_vehicle_button = $Panel/SaveButton
@onready var save_dialog = $SaveDialog
@onready var name_input = $Panel/NameInput
@onready var error_label = $SaveDialog/ErrorLabel
@onready var recycle_button = $Panel/DismantleButton
@onready var load_button = $Panel/LoadButton
@onready var repair_buttom = $Panel/RepairButton

var saw_cursor:Texture = preload("res://assets/icons/saw_cursor.png")

signal block_selected(scene_path: String)
signal vehicle_saved(vehicle_name: String)
signal recycle_mode_toggled(is_recycle_mode: bool)

const GRID_SIZE = 16
const BLOCK_PATHS = {
	"Firepower": "res://blocks/firepower/",
	"Mobility": "res://blocks/mobility/",
	"Command": "res://blocks/command/",
	"Building": "res://blocks/building/",
	"Structual": "res://blocks/structual/",
	"Auxiliary": "res://blocks/auxiliary/"
}

const BLUEPRINT = {
	"BLUEPRINT":"res://vehicles/blueprint/"
}

var item_lists = {}
var is_recycle_mode := false
var is_loading_mode := false  # 新增：标记是否处于加载模式
var original_tab_names := []  # 新增：存储原始标签页名称

# === 蓝图显示功能 ===
var blueprint_ghosts := []  # 存储虚影块的数组
var blueprint_data: Dictionary  # 当前蓝图数据
var is_showing_blueprint := false  # 是否正在显示蓝图
var ghost_data_map = {}  # ghost instance_id -> GhostData

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
var snap_config

# 存储原始连接状态
var original_connections: Dictionary = {}

# 虚影数据类
class GhostData:
	var grid_positions: Array
	var rotation_deg: float

func _ready():
	camera = get_tree().current_scene.find_child("Camera2D") as Camera2D
	build_vehicle_button.pressed.connect(_on_build_vehicle_pressed)
	save_dialog.get_ok_button().pressed.connect(_on_save_confirmed)
	save_dialog.close_requested.connect(_on_save_canceled)
	name_input.text_changed.connect(_on_name_input_changed)
	recycle_button.pressed.connect(_on_recycle_button_pressed)
	#load_button.pressed.connect(_on_load_button_pressed)
	repair_buttom.pressed.connect(_on_repair_button_pressed)
	create_tabs()
	
	save_dialog.hide()
	error_label.hide()
	
	var connect_result = vehicle_saved.connect(_on_vehicle_saved)
	if connect_result == OK:
		print("✅ vehicle_saved Signal connected successfully")
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
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
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
			KEY_F:
				print_connection_points_info()
	
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if is_recycle_mode:
				try_remove_block()
			else:
				try_place_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()  # 右键取消放置

func _process(_delta):
	if is_editing and selected_vehicle:
		camera.sync_rotation_to_vehicle(selected_vehicle)
	
	if is_showing_blueprint and not blueprint_ghosts.is_empty():
		update_ghosts_transform()	
	
	if is_editing and is_recycle_mode and selected_vehicle:
		update_recycle_highlight()
		
	if not is_editing or not current_ghost_block or not selected_vehicle:
		return
	
	if Engine.get_frames_drawn() % 2 == 0:
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		update_ghost_block_position(global_mouse_pos)

# === 修复功能 ===

func clear_tab_container_selection():
	for tab_name in item_lists:
		var item_list = item_lists[tab_name]
		item_list.deselect_all()
		item_list.release_focus()

func _on_repair_button_pressed():
	if not is_editing or not selected_vehicle or not is_showing_blueprint:
		print("修复条件不满足：需要处于编辑模式、选中车辆且显示蓝图")
		return
	
	print("开始修复蓝图缺失部分...")
	repair_blueprint_missing_blocks()

func repair_blueprint_missing_blocks():
	for pos in selected_vehicle.grid.keys():
		var block = selected_vehicle.grid[pos]
		if block is Block:
			if block.current_hp < block.max_hp:
				block.current_hp = block.max_hp
	if not blueprint_data or blueprint_ghosts.is_empty():
		print("没有需要修复的蓝图虚影")
		return
	
	var repaired_count = 0
	var failed_count = 0
	
	# 获取当前车辆已占用的网格位置
	var occupied_grid_positions = {}
	for grid_pos in selected_vehicle.grid:
		occupied_grid_positions[grid_pos] = true
	
	# 遍历所有蓝图虚影
	for ghost in blueprint_ghosts:
		if not is_instance_valid(ghost):
			continue
		
		var ghost_data = get_ghost_data(ghost)
		if not ghost_data:
			continue
		
		# 检查这个虚影的位置是否被占用
		var can_place = true
		for grid_pos in ghost_data.grid_positions:
			if occupied_grid_positions.has(grid_pos):
				can_place = false
				print("无法修复：网格位置 ", grid_pos, " 已被占用")
				break
		
		if can_place:
			# 尝试放置这个块
			if try_place_ghost_block(ghost, ghost_data):
				repaired_count += 1
				# 更新已占用位置
				for grid_pos in ghost_data.grid_positions:
					occupied_grid_positions[grid_pos] = true
			else:
				failed_count += 1
	
	print("修复完成：成功修复 ", repaired_count, " 个块，失败 ", failed_count, " 个块")
	
	# 修复后更新蓝图显示（会重新计算缺失的块）
	if repaired_count > 0:
		update_blueprint_ghosts()

func try_place_ghost_block(ghost: Node2D, ghost_data: GhostData) -> bool:
	# 加载块场景
	var scene_path = ghost.scene_file_path
	if not scene_path or scene_path.is_empty():
		print("错误：无法获取虚影的场景路径")
		return false
	
	var scene = load(scene_path)
	if not scene:
		print("错误：无法加载场景 ", scene_path)
		return false
	
	# 创建新块
	var new_block: Block = scene.instantiate()
	selected_vehicle.add_child(new_block)
	
	# 设置块的位置和旋转
	new_block.global_position = ghost.global_position
	new_block.global_rotation = ghost.global_rotation
	new_block.base_rotation_degree = ghost_data.rotation_deg
	
	# 添加到车辆网格
	var control = selected_vehicle.control
	selected_vehicle._add_block(new_block, new_block.position, ghost_data.grid_positions)
	selected_vehicle.control = control
	
	print("成功修复块: ", new_block.block_name, " 在位置 ", ghost_data.grid_positions)
	return true

# === UI 相关函数 ===
func create_tabs():
	for child in tab_container.get_children():
		child.queue_free()
	
	create_tab_with_itemlist("All")
	
	for category in BLOCK_PATHS:
		create_tab_with_itemlist(category)
	
	for tab_name in item_lists:
		item_lists[tab_name].item_selected.connect(_on_item_selected.bind(tab_name))
	
	# 存储原始标签页名称
	original_tab_names = []
	for i in range(tab_container.get_tab_count()):
		original_tab_names.append(tab_container.get_tab_title(i))

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
	item_list.clear()
	for item in items:
		var idx = item_list.add_item(item.name)
		item_list.set_item_icon(idx, item.icon)
		item_list.set_item_metadata(idx, item.path)

func _on_item_selected(index: int, tab_name: String):
	if is_loading_mode:
		# 在加载模式下，处理车辆选择
		var item_list = item_lists[tab_name]
		var vehicle_name = item_list.get_item_text(index)
		load_selected_vehicle(vehicle_name)
	else:
		# 正常模式下的方块选择
		var item_list = item_lists[tab_name]
		var scene_path = item_list.get_item_metadata(index)
		if scene_path:
			if is_recycle_mode:
				exit_recycle_mode()
			emit_signal("block_selected", scene_path)
			update_description(scene_path)
			if is_editing:
				start_block_placement(scene_path)
				# 放置新块后更新蓝图显示
				update_blueprint_ghosts()

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
	
	# 直接尝试保存，不显示确认弹窗
	try_save_vehicle()

func _on_load_button_pressed():
	if is_loading_mode:
		# 如果已经在加载模式，切换回正常模式
		switch_to_normal_mode()
	else:
		# 切换到加载模式
		switch_to_loading_mode()

func switch_to_loading_mode():
	is_loading_mode = true
	load_button.add_theme_color_override("font_color", Color.CYAN)
	
	# 清空所有标签页
	for tab_name in item_lists:
		item_lists[tab_name].clear()
	
	# 加载蓝图文件夹中的车辆
	load_blueprint_vehicles()

func switch_to_normal_mode():
	is_loading_mode = false
	load_button.remove_theme_color_override("font_color")
	
	# 恢复原始方块列表
	load_all_blocks()
	
	# 恢复原始标签页标题
	for i in range(tab_container.get_tab_count()):
		if i < original_tab_names.size():
			tab_container.set_tab_title(i, original_tab_names[i])
	
	# 清除蓝图显示
	clear_blueprint_ghosts()

func load_blueprint_vehicles():
	var blueprint_dir = DirAccess.open(BLUEPRINT["BLUEPRINT"])
	if not blueprint_dir:
		print("错误: 无法打开蓝图目录 ", BLUEPRINT["BLUEPRINT"])
		return
	
	blueprint_dir.list_dir_begin()
	var file_name = blueprint_dir.get_next()
	var vehicle_names = []
	
	while file_name != "":
		if file_name.ends_with(".json"):
			var vehicle_name = file_name.get_basename()
			vehicle_names.append(vehicle_name)
		file_name = blueprint_dir.get_next()
	
	blueprint_dir.list_dir_end()
	
	# 按字母顺序排序
	vehicle_names.sort()
	
	# 在所有标签页中显示车辆名称
	for tab_name in item_lists:
		var item_list = item_lists[tab_name]
		item_list.clear()
		
		# 设置标签页标题
		var tab_index = tab_container.get_tab_count() - 1
		for i in range(tab_container.get_tab_count()):
			if tab_container.get_tab_control(i) == item_list:
				tab_index = i
				break
		
		if tab_name == "All":
			tab_container.set_tab_title(tab_index, "Vehicles")
		else:
			tab_container.set_tab_title(tab_index, "")
		
		# 添加车辆到列表
		for vehicle_name in vehicle_names:
			var _idx = item_list.add_item(vehicle_name)

func load_selected_vehicle(vehicle_name: String):
	print("显示蓝图虚影: ", vehicle_name)
	
	# 首先切换回正常模式
	switch_to_normal_mode()
	
	# 然后显示选定蓝图的虚影
	var blueprint_path = BLUEPRINT["BLUEPRINT"] + vehicle_name + ".json"
	var file = FileAccess.open(blueprint_path, FileAccess.READ)
	
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		
		if parse_result == OK:
			var blueprint_data_ghost = json.data
			print("成功加载蓝图: ", blueprint_data_ghost["name"])
			
			# 显示蓝图虚影
			show_blueprint_ghosts(blueprint_data_ghost)
			
		else:
			print("错误: 无法解析JSON文件 ", blueprint_path)
	else:
		print("错误: 无法打开文件 ", blueprint_path)

func show_blueprint_ghosts(blueprint: Dictionary):
	if not selected_vehicle:
		print("错误: 没有选中的车辆")
		return
	
	# 清除之前的虚影
	clear_blueprint_ghosts()
	
	# 存储蓝图数据
	blueprint_data = blueprint
	is_showing_blueprint = true
	
	# 获取当前车辆已有的块位置（用于检测哪些块缺失）
	var current_block_positions = {}
	
	for block in selected_vehicle.total_blocks:
		if is_instance_valid(block):
			# 获取块在车辆网格中的位置
			var block_grid_positions = get_block_grid_positions(block)
			for grid_pos in block_grid_positions:
				current_block_positions[grid_pos] = block
	
	print("当前车辆块数量: ", selected_vehicle.blocks.size())
	print("当前占用网格位置: ", current_block_positions.size())
	
	# 分析蓝图并创建缺失块的虚影
	var created_ghosts = 0
	var total_blueprint_blocks = 0
	
	for block_id in blueprint["blocks"]:
		total_blueprint_blocks += 1
		var block_data = blueprint["blocks"][block_id]
		var scene_path = block_data["path"]
		var base_pos = Vector2i(block_data["base_pos"][0], block_data["base_pos"][1])
		var rotation_deg = block_data["rotation"][0]
		
		# 计算这个块在蓝图中的网格位置
		var ghost_grid_positions = calculate_ghost_grid_positions(base_pos, rotation_deg, scene_path)
		
		# 检查这个块是否在当前车辆中缺失
		var is_missing = false
		for grid_pos in ghost_grid_positions:
			if not current_block_positions.has(grid_pos):
				is_missing = true
				break
		
		if is_missing:
			# 创建缺失块的虚影
			create_ghost_block_with_data(scene_path, rotation_deg, ghost_grid_positions)
			created_ghosts += 1
	
	print("蓝图总块数: ", total_blueprint_blocks, ", 缺失块数量: ", created_ghosts)
	print("显示蓝图虚影完成")

func calculate_ghost_grid_positions(base_pos: Vector2i, rotation_deg: float, scene_path: String) -> Array:
	var scene = load(scene_path)
	if not scene:
		print("错误: 无法加载场景 ", scene_path)
		return []
	
	var temp_block = scene.instantiate()
	var block_size = Vector2i(1, 1)
	if temp_block is Block:
		block_size = temp_block.size
	else:
		print("警告: 场景 ", scene_path, " 不是Block类型")
		temp_block.queue_free()
		return []
	
	temp_block.queue_free()
	
	var grid_positions = []
	
	for x in range(block_size.x):
		for y in range(block_size.y):
			var grid_pos: Vector2i
			
			match int(rotation_deg):
				0:
					grid_pos = base_pos + Vector2i(x, y)
				90:
					grid_pos = base_pos + Vector2i(-y, x)
				-90:
					grid_pos = base_pos + Vector2i(y, -x)
				180, -180:
					grid_pos = base_pos + Vector2i(-x, -y)
				_:
					grid_pos = base_pos + Vector2i(x, y)  # 默认情况
			
			grid_positions.append(grid_pos)
	
	return grid_positions

func get_block_grid_positions(block: Block) -> Array:
	var grid_positions = []
	
	# 在车辆网格中查找这个块的所有位置
	for grid_pos in selected_vehicle.grid:
		if selected_vehicle.grid[grid_pos] == block:
			grid_positions.append(grid_pos)
	
	return grid_positions

func get_rectangle_corners_arry(grid_data):
	if grid_data.is_empty():
		return []
	
	var x_coords = []
	var y_coords = []
	
	for coord in grid_data:
		x_coords.append(coord[0])
		y_coords.append(coord[1])
	
	x_coords.sort()
	y_coords.sort()
	
	var min_x = x_coords[0]
	var max_x = x_coords[x_coords.size() - 1]
	var min_y = y_coords[0]
	var max_y = y_coords[y_coords.size() - 1]
	
	var vc_1 = Vector2(min_x * GRID_SIZE , min_y * GRID_SIZE)
	var vc_2 = Vector2(max_x * GRID_SIZE + GRID_SIZE, max_y * GRID_SIZE + GRID_SIZE)
	
	var pos = (vc_1 + vc_2)/2
	
	return pos

func create_ghost_block_with_data(scene_path: String, rotation_deg: float, grid_positions: Array):
	var scene = load(scene_path)
	if not scene:
		print("错误: 无法加载块场景: ", scene_path)
		return
	
	var ghost = scene.instantiate()
	get_tree().current_scene.add_child(ghost)
	
	# 设置虚影外观
	ghost.modulate = Color(0.3, 0.6, 1.0, 0.5)
	ghost.z_index = 45
	ghost.visible = true
	
	# 使用精确的位置计算方法
	var ghost_world_position = calculate_ghost_world_position_precise(grid_positions)
	ghost.global_position = ghost_world_position[0]
	ghost.global_rotation = ghost_world_position[1] + deg_to_rad(rotation_deg)
	
	if ghost.has_method("set_base_rotation_degree"):
		ghost.base_rotation_degree = rotation_deg
	
	# 禁用碰撞
	setup_blueprint_ghost_collision(ghost)
	
	# 存储虚影数据
	var data = GhostData.new()
	data.grid_positions = grid_positions
	data.rotation_deg = rotation_deg
	ghost_data_map[ghost.get_instance_id()] = data
	
	blueprint_ghosts.append(ghost)
	
	print("创建虚影: ", ghost.block_name if ghost is Block else "未知", " 在网格位置 ", grid_positions)

func calculate_ghost_world_position_precise(grid_positions: Array):
	if grid_positions.is_empty():
		return Vector2.ZERO
	
	var local_position = get_rectangle_corners_arry(grid_positions)
	
	# 方法1：使用车辆的第一个网格位置作为参考
	if not selected_vehicle.grid.is_empty():
		var first_grid_pos = selected_vehicle.grid.keys()[0]
		var first_block = selected_vehicle.grid[first_grid_pos]
		var first_gird = []
		for key in selected_vehicle.grid.keys():
			if selected_vehicle.grid[key] == first_block:
				if not first_gird.has(key):
					first_gird.append(key)
		if first_block is Block:
			var first_rotation = deg_to_rad(rad_to_deg(first_block.global_rotation) - first_block.base_rotation_degree)
			
			var first_position = get_rectangle_corners_arry(first_gird)
			
			if first_block:
				
				var local_offset = local_position - first_position
				
				# 将局部偏移旋转到车辆的方向
				var rotated_offset = local_offset.rotated(first_rotation)
				
				# 返回世界坐标
				return [first_block.global_position + rotated_offset, first_rotation]
		
	# 方法2：使用车辆中心点
	return calculate_ghost_world_position_simple(grid_positions)

func calculate_ghost_world_position_simple(grid_positions: Array) -> Vector2:
	# 简单方法：基于车辆中心点计算
	if grid_positions.is_empty():
		return Vector2.ZERO
	
	# 计算网格中心
	var sum_x = 0
	var sum_y = 0
	for pos in grid_positions:
		sum_x += pos.x
		sum_y += pos.y
	
	var center_grid = Vector2(sum_x / float(grid_positions.size()), sum_y / float(grid_positions.size()))
	
	# 转换为世界坐标
	var grid_size = 16
	var local_center = Vector2(center_grid.x * grid_size, center_grid.y * grid_size)
	
	# 考虑车辆的全局变换
	return selected_vehicle.to_global(local_center)

func setup_blueprint_ghost_collision(ghost: Node2D):
	# 禁用所有碰撞形状
	var collision_shapes = ghost.find_children("*", "CollisionShape2D", true)
	for shape in collision_shapes:
		shape.disabled = true
	
	var collision_polygons = ghost.find_children("*", "CollisionPolygon2D", true)
	for poly in collision_polygons:
		poly.disabled = true
	
	# 如果是RigidBody2D，冻结它
	if ghost is RigidBody2D:
		ghost.freeze = true
		ghost.collision_layer = 0
		ghost.collision_mask = 0
	
	if ghost is Block:
		ghost.do_connect = false
	# 禁用所有连接点
	var connection_points = ghost.find_children("*", "ConnectionPoint", true)
	for point in connection_points:
		if point.has_method("set_connection_enabled"):
			point.set_connection_enabled(false)
			
func get_ghost_data(ghost: Node2D) -> GhostData:
	return ghost_data_map.get(ghost.get_instance_id())

func update_ghosts_transform():
	if not is_showing_blueprint or blueprint_ghosts.is_empty():
		return
	
	# 重新计算所有虚影的位置和旋转
	for ghost in blueprint_ghosts:
		if is_instance_valid(ghost):
			# 获取虚影对应的网格位置
			var ghost_data = get_ghost_data(ghost)
			if ghost_data:
				var new_position = calculate_ghost_world_position_precise(ghost_data.grid_positions)
				ghost.global_position = new_position[0]
				ghost.global_rotation = new_position[1] + deg_to_rad(ghost_data.rotation_deg)

func clear_blueprint_ghosts():
	for ghost in blueprint_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	blueprint_ghosts.clear()
	ghost_data_map.clear()
	is_showing_blueprint = false

func update_blueprint_ghosts():
	if is_showing_blueprint and selected_vehicle and blueprint_data:
		# 重新显示蓝图虚影（会清除旧的并创建新的）
		show_blueprint_ghosts(blueprint_data)

func toggle_blueprint_display():
	if is_editing and selected_vehicle:
		if is_showing_blueprint:
			clear_blueprint_ghosts()
			print("隐藏蓝图虚影")
		else:
			# 尝试从车辆获取蓝图数据
			if selected_vehicle.blueprint is Dictionary:
				show_blueprint_ghosts(selected_vehicle.blueprint)
				print("显示蓝图虚影")
			elif selected_vehicle.blueprint is String:
				# 从文件加载蓝图
				var blueprint_path = BLUEPRINT["BLUEPRINT"] + selected_vehicle.blueprint + ".json"
				var file = FileAccess.open(blueprint_path, FileAccess.READ)
				if file:
					var json_string = file.get_as_text()
					file.close()
					var json = JSON.new()
					if json.parse(json_string) == OK:
						show_blueprint_ghosts(json.data)
						print("显示蓝图虚影")
					else:
						print("错误: 无法解析蓝图文件")
				else:
					print("错误: 无法打开蓝图文件")

func try_save_vehicle():
	var vehicle_name = name_input.text.strip_edges()
	
	# 验证名称
	if vehicle_name.is_empty():
		show_error_dialog("Name cannot be empty!")
		return
	
	if vehicle_name.contains("/") or vehicle_name.contains("\\"):
		show_error_dialog("The name cannot contain special characters!")
		return
	
	# 直接保存
	save_vehicle(vehicle_name)

func show_error_dialog(error_message: String):
	error_label.text = error_message
	error_label.show()
	save_dialog.title = "Save Error"
	save_dialog.popup_centered()

func _on_save_confirmed():
	# 确认按钮现在只用于错误确认，关闭弹窗即可
	save_dialog.hide()

func _on_save_canceled():
	save_dialog.hide()

func _on_name_input_changed(_new_text: String):
	error_label.hide()

func _on_recycle_button_pressed():
	if is_recycle_mode:
		exit_recycle_mode()
	else:
		enter_recycle_mode()

func enter_recycle_mode():
	is_recycle_mode = true
	Input.set_custom_mouse_cursor(preload("res://assets/icons/saw_cursor.png"))
	
	# 取消当前块放置
	if current_ghost_block:
		current_ghost_block.visible = false
	
	# 清除 TabContainer 的选择
	clear_tab_container_selection()
	
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
	pass

func find_and_select_vehicle():
	var testground = get_tree().current_scene
	if testground:
		var canvas_layer = testground.find_child("CanvasLayer", false, false)
		if canvas_layer:
			var panels = canvas_layer.get_children()
			for item in range(panels.size() - 1, -1, -1):
				if panels[item] is FloatingPanel and panels[item].selected_vehicle != null and panels[item].visible == true:
					panel_instance = panels[item]
					break
	if testground and panel_instance:
		if panel_instance.selected_vehicle:
			selected_vehicle = panel_instance.selected_vehicle
			name_input.text = selected_vehicle.vehicle_name
			print("Find the vehicle: ", selected_vehicle.vehicle_name)
			return

func enter_editor_mode(vehicle: Vehicle):
	if is_editing:
		exit_editor_mode()
	selected_vehicle = vehicle

	is_editing = true
	
	camera.focus_on_vehicle(selected_vehicle)
	camera.sync_rotation_to_vehicle(selected_vehicle)
	
	print("=== Enter edit mode ===")
	
	enable_all_connection_points_for_editing(true)
	
	vehicle.control = Callable()
	
	show()
	
	# 重置连接点索引
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0
	
	toggle_blueprint_display()
	
	print("=== Edit mode ready ===")

func exit_editor_mode():
	if not is_editing:
		return
	
	if selected_vehicle.check_and_regroup_disconnected_blocks() or selected_vehicle.commands.size() == 0:
		error_label.show()
		if selected_vehicle.check_and_regroup_disconnected_blocks():
			if selected_vehicle.commands.size() == 0:
				error_label.text = "Unconnected Block & No Command"
			else:
				error_label.text = "Unconnected Block"
		else:
			error_label.text = "No Command"
		save_dialog.show()
		save_dialog.title = "Error"
		save_dialog.popup_centered()
		return
	
	for block:Block in selected_vehicle.blocks:
		block.collision_layer = 1
		block.modulate = Color.WHITE  # 重置颜色
	
	# 退出删除模式
	if is_recycle_mode:
		exit_recycle_mode()
	
	clear_tab_container_selection()
	print("=== Exit edit mode ===")
 	
	restore_original_connections()
	if is_recycle_mode:
		is_recycle_mode = false
		Input.set_custom_mouse_cursor(null)
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	# 清除蓝图显示
	clear_blueprint_ghosts()
	
	camera.target_rot = 0.0
	
	hide()
	is_editing = false
	panel_instance = null
	selected_vehicle = null
	print("=== 编辑模式已退出 ===")

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
	

func start_block_placement(scene_path: String):
	if not is_editing or not selected_vehicle:
		return
	
	print("Start placing blocks: ", scene_path.get_file())
	
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
	
	# 重置基础旋转角度
	current_ghost_block.base_rotation_degree = 0
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
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

# === 连接点吸附系统 ===
func update_ghost_block_position(mouse_position: Vector2):
	# 获取附近的车辆连接点
	available_vehicle_points = selected_vehicle.get_available_points_near_position(mouse_position, 20.0)
	available_ghost_points = get_ghost_block_available_connection_points()
	
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		# 没有可用连接点，自由移动
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot# 使用基础旋转
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
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)  # 使用基础旋转
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
			var target_rotation = calculate_aligned_rotation_from_base(vehicle_block)
			# 检查连接点是否可以连接
			if not can_points_connect_with_rotation(vehicle_point, ghost_point, target_rotation):
				continue
				
			var positions = calculate_rotated_grid_positions(vehicle_point, ghost_point)
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

func calculate_aligned_rotation_from_base(vehicle_block: Block) -> float:
	var dir = vehicle_block.base_rotation_degree
	return deg_to_rad(current_ghost_block.base_rotation_degree) + deg_to_rad(-dir) + vehicle_block.global_rotation

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
	var angle_diff = are_rotations_opposite_best(ghost_point_direction, point_a.global_rotation)
	return angle_diff   # 允许稍大的误差，因为是基于基础旋转的对齐

func are_rotations_opposite_best(rot1: float, rot2: float) -> bool:
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
	current_ghost_block.base_rotation_degree += 90
	current_ghost_block.base_rotation_degree = fmod(current_ghost_block.base_rotation_degree + 90, 360) - 90
	
	# 更新幽灵方块显示（使用基础旋转）
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	# 更新位置
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_ghost_block_position(global_mouse_pos)
	
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
		return
	
	if not current_snap_config:
		return
	
	# 断开可能冲突的连接
	var connections_to_disconnect = find_connections_to_disconnect_for_placement()
	disconnect_connections(connections_to_disconnect)
	
	var grid_positions = snap_config.positions
	# 创建新块
	var new_block:Block = current_block_scene.instantiate()
	#new_block.collision_layer = 0
	selected_vehicle.add_child(new_block)
	new_block.global_position = current_snap_config.ghost_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	var control = selected_vehicle.control
	# 计算网格位置并更新
	selected_vehicle._add_block(new_block, new_block.position, grid_positions)
	
	selected_vehicle.control = control
	
	# 继续放置同一类型的块（保持当前基础旋转）
	start_block_placement_with_rotation(current_block_scene.resource_path)
	
	# 放置块后更新蓝图显示
	update_blueprint_ghosts()

func start_block_placement_with_rotation(scene_path: String):
	if not is_editing or not selected_vehicle:
		return
	
	print("Start placing blocks: ", current_ghost_block.block_name, " Basic rotation: ", current_ghost_block.base_rotation_degree, " degree")
	
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
	
	# 保持之前的基础旋转
	current_ghost_block.base_rotation_degree = base_rotation_degree
	current_ghost_block.rotation = deg_to_rad(base_rotation_degree)
	
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
	# 提取重复的连接点计算逻辑
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

# 提取的重复逻辑函数
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
			print("Remove block: ", block_name)
			
			# 移除块后更新蓝图显示
			update_blueprint_ghosts()
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
	clear_tab_container_selection()
	print("放置已取消")

func get_block_size(block: Block) -> Vector2i:
	if block.has_method("get_size"):
		return block.size
	return Vector2i(1, 1)

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
		print("Error: No vehicle selected")
		return
	
	print("Saving vehicle: ", vehicle_name)
	
	var blueprint_data_save = create_blueprint_data(vehicle_name)
	var blueprint_path = "res://vehicles/blueprint/%s.json" % vehicle_name
	
	if save_blueprint(blueprint_data_save, blueprint_path):
		selected_vehicle.vehicle_name = vehicle_name
		selected_vehicle.blueprint = blueprint_data_save
		print("Vehicle saved successfully: ", blueprint_path)
	else:
		show_error_dialog("Failed to save the vehicle")

func create_blueprint_data(vehicle_name: String) -> Dictionary:
	var blueprint_data_save = {
		"name": vehicle_name,
		"blocks": {},
		"vehicle_size": [0, 0],
		"rotation": [0]
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
			var rotation_str = block.base_rotation_degree
			
			blueprint_data_save["blocks"][str(block_counter)] = {
				"name": block.block_name,
				"path": block.scene_file_path,
				"base_pos": [relative_pos.x, relative_pos.y],
				"rotation": [rotation_str],
			}
			block_counter += 1
			processed_blocks[block] = true
	
	blueprint_data_save["vehicle_size"] = [max_x - min_x + 1, max_y - min_y + 1]
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

func save_blueprint(blueprint_data_save: Dictionary, save_path: String) -> bool:
	var dir = DirAccess.open("res://vehicles/blueprint/")
	if not dir:
		DirAccess.make_dir_absolute("res://vehicles/blueprint/")
	
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(blueprint_data_save, "\t"))
		file.close()
		print("Vehicle blueprint has been saved to:", save_path)
		return true
	else:
		push_error("Failed to save file:", FileAccess.get_open_error())
		return false

func update_recycle_highlight():
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	# 重置所有块的颜色
	reset_all_blocks_color()
	
	# 检测鼠标下的块并高亮为红色
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = global_mouse_pos
	query.collision_mask = 1  # 只检测块所在的碰撞层
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is Block and block.get_parent() == selected_vehicle:
			# 将要删除的块变成红色
			block.modulate = Color.RED
			break

# 重置所有块的颜色
func reset_all_blocks_color():
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			block.modulate = Color.WHITE

# 退出删除模式
func exit_recycle_mode():
	if is_recycle_mode:
		is_recycle_mode = false
		Input.set_custom_mouse_cursor(null)
		update_recycle_button()
		
		# 重置所有块的颜色
		if selected_vehicle:
			reset_all_blocks_color()
		
		emit_signal("recycle_mode_toggled", false)
