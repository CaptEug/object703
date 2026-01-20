extends Control
class_name BuildingEditor

# 建筑编辑器UI
@onready var block_list = $BlockList
@onready var building_info = $BuildingInfo
@onready var construction_progress = $ConstructionProgress

var building_system: BuildingSystem
var current_building: Building = null

func _ready():
	building_system = BuildingSystem.new()
	get_tree().current_scene.add_child(building_system)
	
	load_available_blocks()

func load_available_blocks():
	"""加载可用的建筑块"""
	# 清空列表
	if block_list:
		block_list.clear()
	
	# 从指定目录加载建筑块
	var blocks_path = "res://blocks/building/"
	var dir = DirAccess.open(blocks_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tscn"):
				var scene_path = blocks_path + file_name
				var scene = load(scene_path)
				var block = scene.instantiate()
				
				if block is Block:
					var idx = block_list.add_item(block.block_name)
					block_list.set_item_icon(idx, block.get_icon_texture())
					block_list.set_item_metadata(idx, scene_path)
					
					block.queue_free()
			
			file_name = dir.get_next()

func create_new_building():
	"""创建新建筑"""
	current_building = building_system.create_new_building()
	building_system.start_editing_building(current_building)
	update_building_info()

func start_editing_existing_building(building: Building):
	"""开始编辑现有建筑"""
	current_building = building
	building_system.start_editing_building(building)
	update_building_info()

func _on_block_list_item_selected(index: int):
	"""当选择建筑块时"""
	var scene_path = block_list.get_item_metadata(index)
	if scene_path and current_building:
		building_system.add_block_to_building(scene_path)

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if building_system.is_editing_mode:
				building_system.place_current_block()
		
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if building_system.is_editing_mode:
				building_system.stop_editing()
				current_building = null
	
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if building_system.is_editing_mode:
				building_system.stop_editing()
				current_building = null

func update_building_info():
	"""更新建筑信息显示"""
	if not current_building:
		building_info.text = "未选择建筑"
		construction_progress.visible = false
		return
	
	var info = "建筑名称: %s\n" % current_building.building_name
	info += "建筑类型: %s\n" % current_building.building_type
	info += "总质量: %.1f kg\n" % current_building.total_mass
	info += "块数量: %d\n" % current_building.blocks.size()
	info += "尺寸: %s\n" % current_building.building_size
	
	building_info.text = info
	
	# 显示建造进度
	if not current_building.is_constructed:
		construction_progress.visible = true
		construction_progress.value = current_building.construction_progress * 100
	else:
		construction_progress.visible = false

func save_building_blueprint():
	"""保存建筑蓝图"""
	if not current_building:
		return
	
	# 打开保存对话框
	# 这里需要实现保存对话框
	pass

func load_building_blueprint():
	"""加载建筑蓝图"""
	# 打开加载对话框
	# 这里需要实现加载对话框
	pass
