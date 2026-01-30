class_name BuildingEditor
extends Control

# === 颜色配置变量 ===
@export var GHOST_FREE_COLOR = Color(1, 0.3, 0.3, 0.6)
@export var GHOST_SNAP_COLOR = Color(0.6, 1, 0.6, 0.6)
@export var GHOST_BLUEPRINT_COLOR = Color(0.3, 0.6, 1.0, 0.6)
@export var RECYCLE_HIGHLIGHT_COLOR = Color(1, 0.3, 0.3, 0.6)
@export var BLOCK_DIM_COLOR = Color(0.5, 0.5, 0.5, 0.6)

@onready var tab_container = $TabContainer
@onready var description_label = $Panel/RichTextLabel
@onready var build_building_button = $Panel/SaveButton
@onready var save_dialog = $SaveDialog
@onready var name_input = $Panel/NameInput
@onready var error_label = $SaveDialog/ErrorLabel
@onready var recycle_button = $Panel/DismantleButton
@onready var repair_button = $Panel/RepairButton
@onready var mode_button = $Panel/ModeButton

var saw_cursor:Texture = preload("res://assets/icons/saw_cursor.png")
var panel_instance = null

signal block_selected(scene_path: String)
signal building_saved(building_name: String)
signal recycle_mode_toggled(is_recycle_mode: bool)

const GRID_SIZE = 16
const BLOCK_PATHS = {
	"Auxiliary": "res://blocks/auxiliary/",
	"Command": "res://blocks/command/",
	"Firepower": "res://blocks/firepower/",
	"Industrial": "res://blocks/industrial/",
	"Structual": "res://blocks/structual/",
}

const BLUEPRINT_PATH = "res://buildings/blueprint/"
const BLUEPRINT_SAVE_PATH = "res://buildings/blueprint/"

# 编辑系统实例
var building_editing_system: BuildingHullEditingSystem
var turret_editing_system: BuildingTurretEditingSystem

# UI数据
var item_lists = {}
var is_ui_interaction: bool = false

# 编辑器状态变量
var is_editing := false
var selected_building: Building = null
var camera:Camera2D

# 模式变量
var is_building_mode := true
var is_recycle_mode := false

# 蓝图相关
var blueprint_ghosts := []
var blueprint_data: Dictionary
var is_showing_blueprint := false
var ghost_data_map = {}

# === 地图对齐相关 ===
var game_map: GameMap
var tilemap_layer: TileMapLayer
var building_layer: BuildingLayer  # BuildingLayer引用

func _ready():
	# 初始化编辑系统
	building_editing_system = BuildingHullEditingSystem.new()
	building_editing_system.setup(self)
	turret_editing_system = BuildingTurretEditingSystem.new()
	turret_editing_system.setup(self)
	
	_connect_block_buttons()
	camera = get_tree().current_scene.find_child("Camera2D") as Camera2D
	build_building_button.pressed.connect(_on_build_building_pressed)
	save_dialog.get_ok_button().pressed.connect(_on_save_confirmed)
	save_dialog.close_requested.connect(_on_save_canceled)
	name_input.text_changed.connect(_on_name_input_changed)
	recycle_button.pressed.connect(_on_recycle_button_pressed)
	repair_button.pressed.connect(_on_repair_button_pressed)
	mode_button.pressed.connect(_on_mode_button_pressed)
	create_tabs()
	
	save_dialog.hide()
	error_label.hide()
	
	building_saved.connect(_on_building_saved)
	update_recycle_button()
	load_all_blocks()
	
	description_label.bbcode_enabled = true
	description_label.text = ""
	
	update_building_info_display()
	
	# 获取游戏地图和TileMapLayer
	_find_game_map()

func _find_game_map():
	"""查找并获取游戏地图、TileMapLayer和BuildingLayer"""
	var current_scene = get_tree().current_scene
	if current_scene:
		for child in current_scene.get_children():
			if child is GameMap:
				game_map = child
				break
		
		if game_map:
			# 查找TileMapLayer和BuildingLayer
			tilemap_layer = game_map.find_child("GroundLayer") as TileMapLayer
			building_layer = game_map.find_child("BuildingLayer") as BuildingLayer
			
			# 打印调试信息
			if building_layer:
				print("找到BuildingLayer，位置：", building_layer.global_position)
				print("BuildingLayer转换测试：")
				print("  local_to_map(Vector2.ZERO): ", building_layer.local_to_map(Vector2.ZERO))
				print("  map_to_local(Vector2i.ZERO): ", building_layer.map_to_local(Vector2i.ZERO))
			else:
				print("警告: 未找到BuildingLayer节点")
	
	building_editing_system.setup(self)

# === UI管理 ===
func _connect_block_buttons():
	var block_buttons = get_tree().get_nodes_in_group("block_buttons")
	for button in block_buttons:
		if button is BaseButton:
			button.pressed.connect(_on_block_button_pressed)

func _on_block_button_pressed():
	is_ui_interaction = true
	await get_tree().create_timer(0.2).timeout
	is_ui_interaction = false

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

func _get_com_ui_position() -> Vector2:
	var world_com: Vector2 = selected_building.calculate_center_of_mass()
	var camera_global_xform: Transform2D = camera.get_global_transform()
	var relative_to_camera: Vector2 = camera_global_xform.affine_inverse() * world_com
	relative_to_camera *= camera.zoom
	var viewport_center: Vector2 = get_viewport().size / 2
	return viewport_center + relative_to_camera

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
	var item_list = item_lists[tab_name]
	var scene_path = item_list.get_item_metadata(index)
	if scene_path:
		if is_recycle_mode:
			exit_recycle_mode()
		if turret_editing_system.is_turret_editing_mode:
			turret_editing_system.start_block_placement(scene_path)
		else:
			emit_signal("block_selected", scene_path)
			update_description(scene_path)
			if is_editing:
				building_editing_system.start_block_placement(scene_path)
				update_blueprint_ghosts()

func update_description(scene_path: String):
	var scene = load(scene_path)
	var block = scene.instantiate()
	if block:
		_set_font_sizes(16)
		
		description_label.clear()
		description_label.append_text("[b]%s[/b]\n\n" % block.block_name)
		description_label.append_text("TYPE: %s\n" % block.type)
		description_label.append_text("SIZE: %s\n" % str(block.size))
		if block.has_method("get_description"):
			description_label.append_text("DESCRIPTION: %s\n" % block.get_description())
		block.queue_free()

func _set_font_sizes(size: int):
	var font_sizes = ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]
	for font_size in font_sizes:
		description_label.add_theme_font_size_override(font_size, size)

# === 建筑信息显示 ===
func update_building_info_display():
	if not is_editing or not selected_building:
		show_editor_info()
		return
	
	_set_font_sizes(8)
	
	var stats = _calculate_building_stats()
	
	description_label.bbcode_enabled = true
	description_label.clear()
	
	description_label.append_text("Name: %s\n" % (selected_building.building_name if selected_building.building_name else "Unnamed"))
	description_label.append_text("ID: %s\n\n" % selected_building.name)
	
	# 存储容量显示
	var storage_text = "Storage: %d / %d\n" % [stats.used_storage, stats.total_storage]
	description_label.append_text(storage_text)
	
	# 如果存储已满，用红色显示
	if stats.total_storage > 0 and stats.used_storage >= stats.total_storage:
		description_label.append_text("[color=#FF0000]Storage Full![/color]\n\n")
	else:
		description_label.append_text("\n")
	# 建筑模式显示
	if is_building_mode:
		description_label.append_text("\n[b]Mode: Building Edit[/b]")
	else:
		description_label.append_text("\n[b]Mode: Turret Edit[/b]")

func _calculate_building_stats() -> Dictionary:
	if not selected_building:
		return {}
	
	return {
		"total_storage": selected_building.get_total_storage_capacity(),
		"used_storage": selected_building.get_used_storage(),
		"is_operational": selected_building.is_operational(),
		"is_destroyed": selected_building.destroyed,
		"block_count": selected_building.blocks.size()
	}

func show_editor_info():
	description_label.text = "[b]BuildingEditor - Structure Builder[/b]\n\n"
	description_label.append_text("Hotkeys:\n")
	description_label.append_text("• B: Enter/Exit Edit Mode (新建建筑)\n")
	description_label.append_text("• R: Rotate Block\n")
	description_label.append_text("• X: Toggle Delete Mode\n")
	description_label.append_text("• T: Toggle Blueprint Display\n")
	description_label.append_text("• ESC: Cancel Operation\n")
	description_label.append_text("• F: Repair Building\n")
	description_label.append_text("• L: Load Saved Building\n")
	description_label.append_text("\n")
	
	description_label.append_text("[b]Quick Start:[/b]\n")
	description_label.append_text("1. 按 B 键新建一个建筑\n")
	description_label.append_text("2. 从左侧选择方块放置\n")
	description_label.append_text("3. 按 R 旋转方块方向\n")
	description_label.append_text("4. 按 B 再次退出编辑模式\n")
	description_label.append_text("\n")
	
	description_label.append_text("[b]Edit Mode[/b]\n")
	if is_building_mode:
		description_label.append_text("Current: Building Edit Mode\n")
		description_label.append_text("Click turret to edit turret\n")
	else:
		description_label.append_text("Current: Turret Edit Mode\n")
		description_label.append_text("Right-click to exit turret edit\n")

# === 输入处理 ===
func _input(event):
	if event is InputEventKey and event.pressed:
		_handle_key_input(event)
	elif event is InputEventMouseButton and event.pressed:
		if is_ui_interaction or get_viewport().gui_get_hovered_control():
			return
		_handle_mouse_input(event)

func _handle_key_input(event: InputEventKey):
	match event.keycode:
		KEY_O:  # B键：进入/退出建造模式（新建建筑）
			_toggle_edit_mode()
		KEY_ESCAPE:
			_handle_escape_key()
		KEY_R:
			_rotate_ghost_block()
		KEY_X:
			_toggle_recycle_mode()
		KEY_T:
			if is_editing and selected_building:
				toggle_blueprint_display()
		KEY_F:
			if is_editing and selected_building and is_showing_blueprint:
				repair_blueprint_missing_blocks()
		KEY_L:  # L键：加载已保存建筑（待实现）
			if not is_editing:
				_load_building_from_panel()

func _load_building_from_panel():
	# 加载建筑功能待实现
	print("加载建筑功能待实现")

func _handle_mouse_input(event: InputEventMouseButton):
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			_handle_left_click()
		MOUSE_BUTTON_RIGHT:
			_handle_right_click()

func _handle_left_click():
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	# 首先检查是否在炮塔编辑模式
	if turret_editing_system.is_turret_editing_mode:
		_handle_turret_mode_click(global_mouse_pos)
		return
	
	# 建筑模式下的点击处理
	var clicked_block = get_block_at_position(global_mouse_pos)
	
	# 检查是否点击了炮塔
	if clicked_block is TurretRing and not is_recycle_mode:
		_handle_turret_click(clicked_block)
	elif not turret_editing_system.is_turret_editing_mode:
		building_editing_system.handle_left_click()
	else:
		turret_editing_system.handle_left_click()

func _handle_turret_mode_click(global_mouse_pos: Vector2):
	# 如果有虚影块，尝试放置
	if turret_editing_system.current_ghost_block:
		turret_editing_system.handle_left_click()
		return
	
	# 检查是否点击了其他炮塔
	var clicked_block = get_block_at_position(global_mouse_pos)
	
	if clicked_block is TurretRing and clicked_block != turret_editing_system.current_editing_turret:
		_handle_turret_click(clicked_block)
		return
	
	turret_editing_system.handle_left_click()

func _handle_turret_click(turret: TurretRing):
	# 确保炮塔有效
	if not turret or not is_instance_valid(turret):
		return
	
	# 如果已经在编辑这个炮塔，忽略点击
	if turret_editing_system.current_editing_turret == turret:
		return
	
	# 如果正在放置虚影块，忽略炮塔切换
	if turret_editing_system.current_ghost_block:
		return
	
	# 设置当前编辑的炮塔
	turret_editing_system.current_editing_turret = turret
	
	# 切换到炮塔模式
	switch_to_turret_mode()

func _handle_right_click():
	if is_recycle_mode:
		exit_recycle_mode()
		return
	if turret_editing_system.is_turret_editing_mode and turret_editing_system.current_ghost_block == null:
		turret_editing_system.exit_turret_editing_mode()
	elif turret_editing_system.current_ghost_block != null:
		if turret_editing_system.is_turret_editing_mode:
			turret_editing_system.cancel_placement()
	else:
		building_editing_system.cancel_placement()

func _handle_escape_key():
	if turret_editing_system.is_turret_editing_mode:
		turret_editing_system.exit_turret_editing_mode()
		return
	building_editing_system.cancel_placement()

func _rotate_ghost_block():
	if building_editing_system.current_ghost_block:
		building_editing_system.rotate_ghost_connection()
	elif turret_editing_system.current_ghost_block:
		turret_editing_system.rotate_ghost_connection()

func _process(delta):
	if is_editing and selected_building:
		camera.sync_rotation_to_building(selected_building)
	
	if is_showing_blueprint and not blueprint_ghosts.is_empty():
		update_ghosts_transform()	
	
	# 更新方块颜色
	if is_editing and selected_building:
		update_all_block_colors()

	building_editing_system.process(delta)
	turret_editing_system.process(delta)
	
	# 更新建筑信息显示
	update_building_info_display()

# === 中央颜色管理系统 ===
func update_all_block_colors():
	"""统一更新所有方块颜色（中央控制器入口）"""
	if not selected_building:
		return
	
	# 1. 重置所有方块为默认颜色
	reset_all_blocks_to_default()
	
	# 2. 根据当前模式应用特定颜色
	apply_mode_specific_colors()
	
	# 3. 如果有悬停方块，应用悬停效果
	apply_hover_highlight_if_needed()

func reset_all_blocks_to_default():
	"""重置所有方块为默认颜色"""
	for block in selected_building.blocks:
		if is_instance_valid(block):
			block.modulate = Color.WHITE

func apply_mode_specific_colors():
	"""应用模式特定的颜色"""	
	if turret_editing_system.is_turret_editing_mode:
		# 炮塔编辑模式
		apply_turret_editing_colors()
	else:
		# 建筑编辑模式
		apply_building_editing_colors()

func apply_turret_editing_colors():
	"""炮塔编辑模式颜色方案"""
	if not turret_editing_system.current_editing_turret:
		return
	
	var current_turret = turret_editing_system.current_editing_turret
	
	for block in selected_building.blocks:
		if not is_instance_valid(block):
			continue
		
		if block == current_turret:
			# 当前编辑的炮塔：白色
			block.modulate = Color.WHITE
			# 当前炮塔上的所有块：白色
			for turret_block in block.turret_blocks:
				if is_instance_valid(turret_block):
					turret_block.modulate = Color.WHITE
		elif block is TurretRing:
			# 其他炮塔本体：虚化
			block.modulate = BLOCK_DIM_COLOR
			# 其他炮塔上的块：虚化
			for turret_block in block.turret_blocks:
				if is_instance_valid(turret_block):
					turret_block.modulate = BLOCK_DIM_COLOR
		elif not block in current_turret.turret_blocks:
			# 建筑上的其他块：虚化
			block.modulate = BLOCK_DIM_COLOR

func apply_building_editing_colors():
	"""建筑编辑模式颜色方案"""
	for block in selected_building.blocks:
		var block_use = []
		if not is_instance_valid(block):
			continue
		if block is TurretRing:
			# 炮塔上的块：虚化（仅在建筑模式） 
			for turret_block in block.turret_blocks:
				if is_instance_valid(turret_block):
					turret_block.modulate = BLOCK_DIM_COLOR
					block_use.append(turret_block)

func apply_hover_highlight_if_needed():
	"""如果有悬停方块，应用悬停高亮"""
	if not is_recycle_mode:
		return
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	var hovered_block = get_hovered_block(global_mouse_pos)
	if hovered_block:
		hovered_block.modulate = RECYCLE_HIGHLIGHT_COLOR

func get_hovered_block(position: Vector2) -> Block:
	"""获取鼠标悬停的方块"""
	if turret_editing_system.is_turret_editing_mode:
		return turret_editing_system.get_turret_block_at_position(position)
	else:
		return get_block_at_position(position)

# === 状态变更接口 ===
func on_mode_changed():
	"""模式变更时调用"""
	update_all_block_colors()
	update_mode_button_display()

func on_recycle_mode_toggled():
	"""回收模式切换时调用"""
	update_all_block_colors()
	update_recycle_button()

func on_edit_mode_changed():
	"""编辑模式切换时调用"""
	update_all_block_colors()

# === 模式切换 ===
func _on_mode_button_pressed():
	if not is_editing:
		return
	
	if is_building_mode:
		switch_to_turret_mode()
	else:
		switch_to_building_mode()
	
	on_mode_changed()  # 中央控制器管理颜色

func switch_to_turret_mode():
	if not is_editing or not selected_building:
		return
	
	if is_recycle_mode:
		exit_recycle_mode()
	
	building_editing_system.cancel_placement()
	
	is_building_mode = false
	
	var turrets = get_turret_blocks()
	if turrets.is_empty():
		is_building_mode = true
		update_mode_button_display()
		return
	
	var first_turret = turrets[0]
	turret_editing_system.enter_turret_editing_mode(first_turret)
	update_mode_button_display()

func switch_to_building_mode():
	if not is_editing:
		return
	
	if turret_editing_system.is_turret_editing_mode:
		turret_editing_system.exit_turret_editing_mode()
	is_building_mode = true
	update_mode_button_display()

func update_mode_button_display():
	if not mode_button:
		return
	
	if is_building_mode:
		mode_button.tooltip_text = "建筑编辑模式 (点击切换到炮塔编辑)"
	else:
		mode_button.tooltip_text = "炮塔编辑模式 (点击切换回建筑编辑)"

# === 删除模式 ===
func _on_recycle_button_pressed():
	_toggle_recycle_mode()

func _toggle_recycle_mode():
	if is_recycle_mode:
		exit_recycle_mode()
	else:
		enter_recycle_mode()

func enter_recycle_mode():
	is_recycle_mode = true
	Input.set_custom_mouse_cursor(saw_cursor)
	
	building_editing_system.cancel_placement()
	turret_editing_system.cancel_placement()
	
	clear_tab_container_selection()
	
	update_recycle_button()
	on_recycle_mode_toggled()  # 中央控制器管理颜色
	emit_signal("recycle_mode_toggled", is_recycle_mode)

func exit_recycle_mode():
	if is_recycle_mode:
		is_recycle_mode = false
		Input.set_custom_mouse_cursor(null)
		update_recycle_button()
		on_recycle_mode_toggled()  # 中央控制器管理颜色
		
		emit_signal("recycle_mode_toggled", false)

func update_recycle_button():
	if is_recycle_mode:
		recycle_button.add_theme_color_override("font_color", Color.RED)
	else:
		recycle_button.remove_theme_color_override("font_color")

# === 编辑器模式功能 ===
func find_and_select_building():
	# 直接新建建筑
	create_new_building()

func enter_editor_mode(building: Building):
	if is_editing:
		exit_editor_mode()
	selected_building = building

	is_editing = true
	is_building_mode = true
	update_mode_button_display()
	
	if not building_editing_system.is_new_building:
		building_editing_system.is_first_block = false
	
	_cleanup_invalid_blocks()
	
	camera.focus_on_building(selected_building)
	camera.sync_rotation_to_building(selected_building)
	
	building_editing_system.enable_all_connection_points_for_editing(true)
	
	selected_building.is_assembled = false
	show()
	
	building_editing_system.reset_connection_indices()
	
	toggle_blueprint_display()
	update_building_info_display()
	
	on_edit_mode_changed()  # 中央控制器管理颜色

func _cleanup_invalid_blocks():
	for block in selected_building.get_children():
		if block is Block and block.collision_layer == 1:
			var has_command = false
			for connected_block in block.get_all_connected_blocks():
				if connected_block is Command or block is Command:
					has_command = true
			if not has_command:
				selected_building.remove_block(block, true)

func _toggle_edit_mode():
	if is_editing:
		exit_editor_mode()
		building_editing_system.cancel_placement()
		turret_editing_system.cancel_placement()
	else:
		# 直接创建新建筑，而不是查找现有建筑
		create_new_building()

func exit_editor_mode():
	if not is_editing:
		return
	
	is_building_mode = true
	update_mode_button_display()
	
	if turret_editing_system.is_turret_editing_mode:
		turret_editing_system.exit_turret_editing_mode()
	
	if selected_building.check_and_regroup_disconnected_blocks() or selected_building.commands.size() == 0:
		_show_exit_error_dialog()
		return
	
	for block:Block in selected_building.blocks:
		block.modulate = Color.WHITE
	
	building_editing_system.is_new_building = false
	building_editing_system.is_first_block = true
	
	if is_recycle_mode:
		exit_recycle_mode()
	clear_tab_container_selection()
 	
	building_editing_system.restore_original_connections()
	
	building_editing_system.cancel_placement()
	
	clear_blueprint_ghosts()
	
	camera.target_rot = 0.0
	
	hide()
	is_editing = false
	panel_instance = null
	selected_building = null
	update_building_info_display()

func _show_exit_error_dialog():
	error_label.show()
	if selected_building.check_and_regroup_disconnected_blocks():
		if selected_building.commands.size() == 0:
			error_label.text = "Unconnected Block & No Command"
		else:
			error_label.text = "Unconnected Block"
	else:
		error_label.text = "No Command"
	save_dialog.show()
	save_dialog.title = "Error"
	save_dialog.popup_centered()

# === 蓝图功能 ===
func toggle_blueprint_display():
	if is_editing and selected_building:
		if is_showing_blueprint:
			clear_blueprint_ghosts()
		else:
			if selected_building.blueprint is Dictionary:
				show_blueprint_ghosts(selected_building.blueprint)
			elif selected_building.blueprint is String:
				load_blueprint_from_file(selected_building.blueprint)

func show_blueprint_ghosts(blueprint: Dictionary):
	if not selected_building or blueprint.size() == 0:
		return
	
	clear_blueprint_ghosts()
	
	blueprint_data = blueprint
	is_showing_blueprint = true
	
	var current_block_positions = _get_current_block_positions()
	var created_ghosts = 0
	
	for block_id in blueprint["blocks"]:
		var block_data = blueprint["blocks"][block_id]
		var scene_path = block_data["path"]
		var base_pos = Vector2i(block_data["base_pos"][0], block_data["base_pos"][1])
		var rotation_deg = block_data["rotation"][0]
		
		var ghost_grid_positions = calculate_ghost_grid_positions(base_pos, rotation_deg, scene_path)
		
		var is_missing = false
		for grid_pos in ghost_grid_positions:
			if not current_block_positions.has(grid_pos):
				is_missing = true
				break
		
		if is_missing:
			create_ghost_block_with_data(scene_path, rotation_deg, ghost_grid_positions)
			created_ghosts += 1

func _get_current_block_positions() -> Dictionary:
	var positions = {}
	for grid_pos in selected_building.grid:
		positions[grid_pos] = selected_building.grid[grid_pos]
	return positions

func calculate_ghost_grid_positions(base_pos: Vector2i, rotation_deg: float, scene_path: String) -> Array:
	var scene = load(scene_path)
	if not scene:
		return []
	
	var temp_block = scene.instantiate()
	var block_size = Vector2i(1, 1)
	if temp_block is Block:
		block_size = temp_block.size
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
					grid_pos = base_pos + Vector2i(x, y)
			
			grid_positions.append(grid_pos)
	
	return grid_positions

func create_ghost_block_with_data(scene_path: String, rotation_deg: float, grid_positions: Array):
	var scene = load(scene_path)
	if not scene:
		return
	
	var ghost = scene.instantiate()
	get_tree().current_scene.add_child(ghost)
	
	ghost.modulate = GHOST_BLUEPRINT_COLOR
	ghost.z_index = 45
	ghost.visible = true
	
	var ghost_world_position = calculate_ghost_world_position_precise(grid_positions)
	ghost.global_position = ghost_world_position[0]
	ghost.global_rotation = ghost_world_position[1] + deg_to_rad(rotation_deg)
	
	ghost.base_rotation_degree = rotation_deg
	
	setup_blueprint_ghost_collision(ghost)
	
	var data = GhostData.new()
	data.grid_positions = grid_positions
	data.rotation_deg = rotation_deg
	ghost_data_map[ghost.get_instance_id()] = data
	
	blueprint_ghosts.append(ghost)

func calculate_ghost_world_position_precise(grid_positions: Array):
	if grid_positions.is_empty():
		return [Vector2.ZERO, 0.0]
	
	var local_position = get_rectangle_corners(grid_positions)
	
	if not selected_building.grid.is_empty():
		var first_grid_pos = selected_building.grid.keys()[0]
		var first_block = selected_building.grid[first_grid_pos]
		var first_grid = []
		for key in selected_building.grid.keys():
			if selected_building.grid[key] == first_block and not first_grid.has(key):
				first_grid.append(key)
		if first_block is Block:
			var first_rotation = deg_to_rad(rad_to_deg(first_block.global_rotation) - first_block.base_rotation_degree)
			var first_position = get_rectangle_corners(first_grid)
			
			if first_block:
				var local_offset = local_position - first_position
				var rotated_offset = local_offset.rotated(first_rotation)
				return [first_block.global_position + rotated_offset, first_rotation]
	
	return [calculate_ghost_world_position_simple(grid_positions), 0.0]

func calculate_ghost_world_position_simple(grid_positions: Array) -> Vector2:
	if grid_positions.is_empty():
		return Vector2.ZERO
	
	var sum_x = 0
	var sum_y = 0
	for pos in grid_positions:
		sum_x += pos.x
		sum_y += pos.y
	
	var center_grid = Vector2(sum_x / float(grid_positions.size()), sum_y / float(grid_positions.size()))
	var local_center = Vector2(center_grid.x * GRID_SIZE, center_grid.y * GRID_SIZE)
	
	return selected_building.to_global(local_center)

func setup_blueprint_ghost_collision(ghost: Node2D):
	# 禁用碰撞
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
	
	if ghost is Block:
		ghost.do_connect = false
	
	var connection_points = ghost.find_children("*", "Connector", true)
	for point in connection_points:
		if point.has_method("set_connection_enabled"):
			point.set_connection_enabled(false)

func get_ghost_data(ghost: Node2D) -> GhostData:
	return ghost_data_map.get(ghost.get_instance_id())

func update_ghosts_transform():
	if not is_showing_blueprint or blueprint_ghosts.is_empty():
		return
	
	for ghost in blueprint_ghosts:
		if is_instance_valid(ghost):
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
	if is_showing_blueprint and selected_building and blueprint_data:
		show_blueprint_ghosts(blueprint_data)

func get_rectangle_corners(grid_data):
	if grid_data.is_empty():
		return Vector2.ZERO
	
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
	
	return (vc_1 + vc_2)/2

# === 修复功能 ===
func _on_repair_button_pressed():
	if not is_editing or not selected_building or not is_showing_blueprint:
		return
	
	repair_blueprint_missing_blocks()

func repair_blueprint_missing_blocks():
	# 修复建筑现有块的HP
	for block in selected_building.blocks:
		if is_instance_valid(block) and block.current_hp < block.max_hp:
			block.current_hp = block.max_hp
	
	if not blueprint_data or blueprint_ghosts.is_empty():
		return
	
	var occupied_grid_positions = {}
	for grid_pos in selected_building.grid:
		occupied_grid_positions[grid_pos] = true
	
	var repaired_count = 0
	
	for ghost in blueprint_ghosts:
		if not is_instance_valid(ghost):
			continue
		
		var ghost_data = get_ghost_data(ghost)
		if not ghost_data:
			continue
		
		var can_place = true
		for grid_pos in ghost_data.grid_positions:
			if occupied_grid_positions.has(grid_pos):
				can_place = false
				break
		
		if can_place and try_place_ghost_block(ghost, ghost_data):
			repaired_count += 1
			for grid_pos in ghost_data.grid_positions:
				occupied_grid_positions[grid_pos] = true
	
	if repaired_count > 0:
		update_blueprint_ghosts()

func try_place_ghost_block(ghost: Node2D, ghost_data: GhostData) -> bool:
	var scene_path = ghost.scene_file_path
	if not scene_path or scene_path.is_empty():
		return false
	
	var scene = load(scene_path)
	if not scene:
		return false
	
	var new_block: Block = scene.instantiate()
	selected_building.add_child(new_block)
	
	new_block.global_position = ghost.global_position
	new_block.global_rotation = ghost.global_rotation
	new_block.base_rotation_degree = ghost_data.rotation_deg
	
	selected_building._add_block(new_block, new_block.position, ghost_data.grid_positions)
	return true

func load_blueprint_from_file(blueprint_name: String):
	var blueprint_path = BLUEPRINT_PATH + blueprint_name + ".json"
	var file = FileAccess.open(blueprint_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		var json = JSON.new()
		if json.parse(json_string) == OK:
			show_blueprint_ghosts(json.data)
		else:
			print("错误: 无法解析蓝图文件")
	else:
		print("错误: 无法打开蓝图文件")

# === 新建建筑功能（对齐到地图格子） ===
func create_new_building():
	if is_editing:
		exit_editor_mode()
		if is_editing:
			return
	var new_building = Building.new()
	new_building.building_name = "NewBuilding_" + str(Time.get_unix_time_from_system())
	new_building.blueprint = {}
	
	# 获取建筑位置（优先使用相机位置）
	var building_position = Vector2(500, 300)
	if camera:
		building_position = camera.global_position
	
	# 对齐到地图格子（如果找到TileMapLayer）
	if tilemap_layer:
		building_position = align_position_to_tilemap(building_position)
	
	new_building.global_position = building_position
	
	var current_scene = get_tree().current_scene
	current_scene.add_child(new_building)
	
	enter_editor_mode_with_new_building(new_building)

func enter_editor_mode_with_new_building(building: Building):
	selected_building = building
	building_editing_system.is_new_building = true
	building_editing_system.is_first_block = true
	name_input.text = ""
	enter_editor_mode(building)

# === 地图对齐辅助函数 ===
func align_position_to_tilemap(position: Vector2) -> Vector2:
	"""将位置对齐到TileMap的格子"""
	if not tilemap_layer:
		return position
	
	# 将世界坐标转换为TileMap的格子坐标
	var cell = tilemap_layer.local_to_map(position)
	
	# 计算格子中心的世界坐标
	var aligned_position = tilemap_layer.map_to_local(cell)
	
	# 确保对齐到GRID_SIZE的倍数（16x16格子）
	aligned_position.x = round(aligned_position.x / GRID_SIZE) * GRID_SIZE
	aligned_position.y = round(aligned_position.y / GRID_SIZE) * GRID_SIZE
	
	return aligned_position

func align_block_position(position: Vector2) -> Vector2:
	"""将方块位置对齐到格子"""
	# 确保对齐到GRID_SIZE的倍数
	var aligned_x = round(position.x / GRID_SIZE) * GRID_SIZE
	var aligned_y = round(position.y / GRID_SIZE) * GRID_SIZE
	return Vector2(aligned_x, aligned_y)

# === 保存功能 ===
func _on_build_building_pressed():
	try_save_building()

func try_save_building():
	var building_name = name_input.text.strip_edges()
	
	if building_name.is_empty():
		show_error_dialog("Name cannot be empty!")
		return
	
	if building_name.contains("/") or building_name.contains("\\"):
		show_error_dialog("The name cannot contain special characters!")
		return
	
	save_building_to_tilemap(building_name)

func _on_building_saved(building_name: String):
	save_building_to_tilemap(building_name)

func save_building_to_tilemap(building_name: String):
	if not selected_building:
		print("Error: No building selected")
		return
	
	# 确保BuildingLayer存在
	ensure_building_layer()
	
	if not building_layer:
		print("Error: BuildingLayer not found")
		show_error_dialog("Cannot find BuildingLayer!")
		return
	
	# 更新建筑名称
	selected_building.building_name = building_name
	
	# 更新所有已放置的方块到BuildingLayer
	update_all_blocks_to_tilemap()
	
	# 显示成功消息
	show_success_dialog("Building saved to TileMap!")

func ensure_building_layer():
	"""确保BuildingLayer存在，如果不存在则尝试获取"""
	if not building_layer:
		# 尝试从当前场景中获取BuildingLayer
		var current_scene = get_tree().current_scene
		if current_scene:
			building_layer = current_scene.find_child("BuildingLayer") as BuildingLayer
			if building_layer:
				print("重新获取到BuildingLayer")
			else:
				print("警告: 仍然无法找到BuildingLayer")

# === 关键功能：每次放置方块时存储到BuildingLayer ===
func update_block_to_tilemap(block: Block, grid_positions: Array):
	"""将单个方块更新到BuildingLayer的layerdata字典中"""
	if not building_layer or not selected_building:
		return
	
	# 确保建筑有名称
	var building_name = selected_building.building_name
	if not building_name or building_name.is_empty():
		building_name = "Unnamed_" + str(selected_building.get_instance_id())
		selected_building.building_name = building_name
	
	# 获取TileMap的单元格大小（默认16x16）
	var tile_size = building_layer.tile_set.tile_size if building_layer.tile_set else Vector2i(16, 16)
	
	# 获取建筑的世界位置
	var building_world_pos = selected_building.global_position
	
	# 遍历方块的每个小格
	for i in range(grid_positions.size()):
		var grid_pos_array = grid_positions[i]
		var grid_pos = Vector2i(grid_pos_array[0], grid_pos_array[1])
		
		# 1. 计算建筑局部坐标
		var building_local = Vector2(grid_pos) * GRID_SIZE
		
		# 2. 考虑建筑的旋转
		var rotated_local = building_local.rotated(selected_building.global_rotation)
		
		# 3. 计算世界坐标
		var world_pos = building_world_pos + rotated_local
		
		# 4. 计算相对于TileMap的坐标
		var tilemap_global_pos = building_layer.global_position
		var relative_to_tilemap = world_pos - tilemap_global_pos
		
		# 5. 转换为TileMap网格坐标
		var tilemap_grid_pos = building_layer.local_to_map(relative_to_tilemap)
		
		# 存储数据
		building_layer.layerdata[grid_pos] = {
			"building_name": building_name,
			"block_name": block.block_name,
			"block_path": block.scene_file_path,
			"rotation": block.base_rotation_degree,
			"hp": block.current_hp,
			"block_size": [block.size.x, block.size.y],
			"grid_pos": [grid_pos.x, grid_pos.y]
		}
	
	# 更新TileMap显示
	building_layer.update_from_layerdata()

func find_base_grid_position(grid_positions: Array, block: Block) -> Vector2i:
	"""找到方块的基准网格位置（通常是左上角）"""
	if grid_positions.is_empty():
		return Vector2i(0, 0)
	
	# 找出最小的x和y坐标
	var min_x = grid_positions[0][0]
	var min_y = grid_positions[0][1]
	
	for pos_array in grid_positions:
		min_x = min(min_x, pos_array[0])
		min_y = min(min_y, pos_array[1])
	
	return Vector2i(min_x, min_y)

func remove_block_from_tilemap(block: Block, grid_positions: Array):
	"""从BuildingLayer的layerdata字典中移除方块"""
	if not building_layer or not selected_building:
		return
	
	# 计算方块的基准位置
	var base_grid_pos = find_base_grid_position(grid_positions, block)
	
	# 对于该方块的每个网格位置
	for grid_pos_array in grid_positions:
		var grid_pos = Vector2i(grid_pos_array[0], grid_pos_array[1])
		
		# 计算方块在建筑局部坐标系中的位置
		var block_local_pos = Vector2(grid_pos) * GRID_SIZE
		
		# 考虑建筑的旋转
		var rotated_pos = block_local_pos.rotated(selected_building.global_rotation)
		
		# 计算世界坐标
		var world_pos = selected_building.global_position + rotated_pos
		
		# 转换为TileMap的网格坐标
		var tilemap_grid_pos = building_layer.local_to_map(world_pos)
		
		# 从layerdata中移除
		if building_layer.layerdata.has(tilemap_grid_pos):
			var data = building_layer.layerdata[tilemap_grid_pos]
			# 只移除属于该方块基准位置的格子
			if data.get("base_grid_pos", []) == [base_grid_pos.x, base_grid_pos.y]:
				building_layer.layerdata.erase(tilemap_grid_pos)
	
	# 更新TileMap显示
	building_layer.update_from_layerdata()

func update_all_blocks_to_tilemap():
	"""将所有方块更新到BuildingLayer"""
	if not building_layer or not selected_building:
		return
	
	# 清除该建筑可能已有的旧数据
	_remove_existing_building_data()
	
	# 遍历建筑中的所有方块
	for grid_pos in selected_building.grid:
		var block = selected_building.grid[grid_pos]
		if block:
			# 收集该方块占据的所有网格位置
			var block_grid_positions = []
			for pos in selected_building.grid:
				if selected_building.grid[pos] == block:
					block_grid_positions.append([pos.x, pos.y])
			
			# 更新到TileMap
			update_block_to_tilemap(block, block_grid_positions)

func _remove_existing_building_data():
	"""清除该建筑可能已有的旧数据"""
	if not building_layer or not selected_building:
		return
	
	var building_name = selected_building.building_name
	var keys_to_remove = []
	
	for grid_pos in building_layer.layerdata:
		var data = building_layer.layerdata[grid_pos]
		if data["building_name"] == building_name:
			keys_to_remove.append(grid_pos)
	
	for key in keys_to_remove:
		building_layer.layerdata.erase(key)

# === 炮塔相关的TileMap更新 ===
func update_turret_block_to_tilemap(turret: TurretRing, turret_block: Block, turret_grid_pos: Vector2i):
	"""将炮塔上的方块更新到BuildingLayer"""
	if not building_layer or not selected_building:
		return
	
	# 确保建筑有名称
	var building_name = selected_building.building_name
	if not building_name or building_name.is_empty():
		building_name = "Unnamed_" + str(selected_building.get_instance_id())
		selected_building.building_name = building_name
	
	# 计算炮塔座圈的世界位置
	var turret_world_pos = turret.global_position
	
	# 计算炮塔上方块相对于炮塔座圈的位置
	var block_local_pos = Vector2(turret_grid_pos) * GRID_SIZE
	
	# 考虑炮塔的旋转
	var rotated_pos = block_local_pos.rotated(turret.global_rotation)
	
	# 计算世界坐标
	var world_pos = turret_world_pos + rotated_pos
	
	# 转换为TileMap的网格坐标
	var tilemap_grid_pos = building_layer.local_to_map(world_pos)
	
	# 存储简化的方块数据到layerdata
	building_layer.layerdata[tilemap_grid_pos] = {
		"building_name": building_name,
		"block_name": turret_block.block_name,
		"block_path": turret_block.scene_file_path,
		"rotation": turret_block.base_rotation_degree,
		"hp": turret_block.current_hp,
		"base_grid_pos": [turret_grid_pos.x, turret_grid_pos.y],  # 炮塔上方块的基准位置
		"block_size": [1, 1],                                     # 炮塔上方块通常为1x1
		"grid_offset": [0, 0],                                    # 偏移为0
		"is_turret_block": true                                   # 标记为炮塔上的方块
	}
	
	# 更新TileMap显示
	building_layer.update_from_layerdata()

# === 显示功能 ===
func show_success_dialog(success_message: String):
	error_label.text = success_message
	error_label.add_theme_color_override("font_color", Color.GREEN)
	error_label.show()
	save_dialog.title = "Save Success"
	save_dialog.popup_centered()
	
	# 延迟恢复颜色
	await get_tree().create_timer(2.0).timeout
	error_label.remove_theme_color_override("font_color")

func show_error_dialog(error_message: String):
	error_label.text = error_message
	error_label.show()
	save_dialog.title = "Save Error"
	save_dialog.popup_centered()

func _on_save_confirmed():
	save_dialog.hide()

func _on_save_canceled():
	save_dialog.hide()

func _on_name_input_changed(_new_text: String):
	error_label.hide()

func clear_tab_container_selection():
	for tab_name in item_lists:
		var item_list = item_lists[tab_name]
		item_list.deselect_all()
		item_list.release_focus()

# === 辅助函数 ===
func get_turret_blocks() -> Array:
	var turrets = []
	if not selected_building:
		return turrets
	
	for block in selected_building.blocks:
		if is_instance_valid(block) and block is TurretRing:
			turrets.append(block)
	
	return turrets

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

# === 虚影数据类 ===
class GhostData:
	var grid_positions: Array
	var rotation_deg:  float

func calculate_offset_by_rotation(local_pos: Vector2i, rotation: int) -> Vector2i:
	"""根据旋转计算偏移"""
	match rotation:
		0:
			return local_pos
		90:
			return Vector2i(-local_pos.y, local_pos.x)
		-90:
			return Vector2i(local_pos.y, -local_pos.x)
		180, -180:
			return -local_pos
		_:
			return local_pos

func _ensure_blueprint_directory():
	"""确保蓝图目录存在"""
	var dir = DirAccess.open("res://")
	if dir:
		if not dir.dir_exists("buildings"):
			dir.make_dir("buildings")
			print("创建目录: res://buildings/")
		
		var buildings_dir = DirAccess.open("res://buildings/")
		if buildings_dir:
			if not buildings_dir.dir_exists("blueprint"):
				buildings_dir.make_dir("blueprint")
				print("创建蓝图目录: res://buildings/blueprint/")
	else:
		print("错误: 无法访问res://目录")

# 修改放置方块的方法，添加即时保存
func on_block_placed(block: Block, grid_positions: Array):
	"""当方块被放置时调用，更新到BuildingLayer"""
	update_block_to_tilemap(block, grid_positions)
	_save_building_blueprint_immediately()  # 立即保存

func on_block_removed(block: Block, grid_positions: Array):
	"""当方块被移除时调用，从BuildingLayer中删除"""
	remove_block_from_tilemap(block, grid_positions)
	_save_building_blueprint_immediately()  # 立即保存

func on_turret_block_placed(turret: TurretRing, turret_block: Block, turret_grid_pos: Vector2i):
	"""当炮塔上的方块被放置时调用，更新到BuildingLayer"""
	update_turret_block_to_tilemap(turret, turret_block, turret_grid_pos)
	_save_building_blueprint_immediately()  # 立即保存

func _save_building_blueprint_immediately():
	"""立即保存建筑蓝图到JSON文件"""
	if not is_editing or not selected_building:
		return
	
	var building_name = selected_building.building_name
	if not building_name or building_name.is_empty():
		building_name = "Unnamed_" + str(selected_building.get_instance_id())
		selected_building.building_name = building_name
	
	print("=== 立即保存蓝图 ===")
	
	# 收集建筑的所有方块数据
	var building_data = _collect_building_data_for_blueprint()
	
	# 保存到JSON文件
	var file_path = BLUEPRINT_SAVE_PATH + building_name + ".json"
	_save_json_file_immediately(file_path, building_data)
	
	print("蓝图已保存: ", file_path)

func _collect_building_data_for_blueprint() -> Dictionary:
	"""收集建筑的完整数据用于蓝图保存"""
	var building_data = {
		"version": "1.0",
		"name": selected_building.building_name,
		"created_time": Time.get_datetime_string_from_system(),
		"blocks": {}
	}
	
	# 按方块分组，避免重复
	var processed_blocks = {}
	var block_index = 0
	
	# 遍历建筑网格中的所有方块
	for grid_pos in selected_building.grid:
		var block = selected_building.grid[grid_pos]
		
		if not block:
			continue
		
		# 创建方块唯一标识符
		var block_key = str(block.get_instance_id())
		
		# 如果这个方块已经处理过，跳过
		if processed_blocks.has(block_key):
			continue
		
		processed_blocks[block_key] = true
		
		# 收集该方块占据的所有网格位置
		var block_grid_positions = []
		for pos in selected_building.grid:
			if selected_building.grid[pos] == block:
				block_grid_positions.append([pos.x, pos.y])
		
		# 计算方块的基准位置
		var base_pos = find_base_grid_position(block_grid_positions, block)
		
		# 添加到方块数据
		building_data["blocks"][str(block_index)] = {
			"path": block.scene_file_path,
			"name": block.block_name,
			"size": [block.size.x, block.size.y],
			"rotation": block.base_rotation_degree,
			"hp": block.current_hp,
			"max_hp": block.max_hp,
			"base_pos": [base_pos.x, base_pos.y],
			"grid_positions": block_grid_positions
		}
		
		block_index += 1
	
	print("收集到 ", block_index, " 个方块数据")
	return building_data

func _save_json_file_immediately(file_path: String, data: Dictionary):
	"""立即保存数据到JSON文件"""
	# 创建JSON字符串
	var json_string = JSON.stringify(data, "\t")
	
	# 保存到文件
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("JSON文件已保存: ", file_path)
	else:
		print("错误: 无法保存JSON文件: ", file_path)
		print("错误代码: ", FileAccess.get_open_error())
