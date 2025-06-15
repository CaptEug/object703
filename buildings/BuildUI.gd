# BuildUI.gd
extends CanvasLayer

@export var block_preview_scene: PackedScene
@export var block_spacing := 120

var factory: Factory = null
var dragged_block: Control = null
var drag_offset := Vector2.ZERO
var build_area_rect := Rect2()

func _ready():
	# 设置建造区域
	build_area_rect = Rect2(
		Vector2(get_viewport().size.x - factory.build_area_size.x, 
			   get_viewport().size.y - factory.build_area_size.y) / 2,
		factory.build_area_size
	)
	
	# 创建可用模块列表
	create_block_previews()

func create_block_previews():
	var start_x = 50
	var y = get_viewport().size.y - 150
	
	for i in range(factory.available_blocks.size()):
		var block_scene = factory.available_blocks[i]
		var block_instance = block_scene.instantiate()
		var preview = block_preview_scene.instantiate()
		
		preview.position = Vector2(start_x + i * block_spacing, y)
		preview.set_block_data(block_instance)
		preview.connect("start_drag", _on_block_drag_started)
		add_child(preview)

func _on_block_drag_started(preview, offset):
	dragged_block = preview
	drag_offset = offset

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and dragged_block:
			# 放置模块
			if build_area_rect.has_point(event.position):
				place_block_in_build_area(event.position - drag_offset)
			dragged_block = null
		
	elif event is InputEventMouseMotion and dragged_block:
		dragged_block.position = event.position - drag_offset

func place_block_in_build_area(position: Vector2):
	var block = dragged_block.block_data.duplicate()
	block.position = position
	
	# 检查是否超出建造区域限制
	var grid_pos = Vector2i(position / factory.GRID_SIZE)
	if grid_pos.x < 0 or grid_pos.y < 0 or \
	   grid_pos.x > factory.max_vehicle_size.x or \
	   grid_pos.y > factory.max_vehicle_size.y:
		return
	
	add_child(block)
