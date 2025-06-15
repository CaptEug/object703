extends CanvasLayer

@export var block_preview_scene: PackedScene = preload("res://buildings/BlockPreview.tscn")
@export var block_spacing := Vector2(120, 0)

var factory: Factory = null
var dragged_block: Control = null
var drag_offset := Vector2.ZERO
var build_area_rect := Rect2()

func _ready():
	setup_build_area()
	create_block_palette()

func setup_build_area():
	var viewport_size = get_viewport().get_visible_rect().size
	build_area_rect = Rect2(
		(viewport_size - factory.build_area_size) / 2,
		factory.build_area_size
	)
	$BuildArea.color = Color(0.2, 0.2, 0.2, 0.5)  # 半透明建造区域

func create_block_palette():
	var start_pos = Vector2(50, get_viewport().size.y - 150)
	
	for i in range(factory.available_blocks.size()):
		var block_scene = factory.available_blocks[i]
		if not block_scene: continue
		
		var preview = block_preview_scene.instantiate()
		preview.position = start_pos + block_spacing * i
		preview.setup(block_scene)
		preview.start_drag.connect(_on_block_drag_start)
		$BlockPalette.add_child(preview)

func _on_block_drag_start(preview: Control, offset: Vector2):
	dragged_block = preview
	drag_offset = offset

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and dragged_block:
			try_place_block(event.position - drag_offset)
			dragged_block = null
		
	elif event is InputEventMouseMotion and dragged_block:
		dragged_block.position = event.position - drag_offset

func try_place_block(position: Vector2):
	if not build_area_rect.has_point(position): return
	
	var block_scene: PackedScene = dragged_block.block_scene
	var block = block_scene.instantiate()
	block.position = position
	
	# 网格对齐和边界检查
	var grid_pos = Vector2i(position / factory.GRID_SIZE)
	if grid_pos.x < 0 or grid_pos.y < 0 or \
	   grid_pos.x >= factory.max_vehicle_size.x or \
	   grid_pos.y >= factory.max_vehicle_size.y:
		return
	
	$BuildArea.add_child(block)
