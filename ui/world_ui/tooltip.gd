extends Panel

@onready var textlabel: RichTextLabel = $RichTextLabel
@onready var grid_container: GridContainer = $GridContainer

@export var padding: Vector2 = Vector2(16, 32)

var _last_block: Node = null

func _ready() -> void:
	visible = false
	grid_container.visible = false


func _physics_process(_delta: float) -> void:
	if get_viewport().gui_get_hovered_control():
		visible = false
		return
	var mouse_pos = get_tree().current_scene.get_local_mouse_position()
	var space_state = get_world_2d().direct_space_state
	var query:= PhysicsPointQueryParameters2D.new()
	query.position = mouse_pos
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	global_position = get_viewport().get_mouse_position() + Vector2(16, 16)
	
	var results = space_state.intersect_point(query)
	var vehicle:Vehicle
	var maplayer:TileMapLayer

	for hit in results:
		var c = hit.collider
		if c is Vehicle:
			vehicle = c
		elif c is TileMapLayer:
			maplayer = c

	if vehicle:
		show_block_in_vehicle(vehicle, query.position)
		return
	elif maplayer:
		show_tile(maplayer, query.position)
		return
	
	# ---- 鼠标移出或未检测到 ----
	if visible:
		visible = false
	_clear_grid()
	call_deferred("update_panel_size")
	_last_block = null


func show_block_in_vehicle(vehicle:Vehicle, pos:Vector2):
	visible = true
	var cell_pos := vehicle.world_to_cell(pos)
	var block := vehicle.get_block(cell_pos)
	# --- 基本信息 ---
	if block:
		textlabel.text = block.block_name + "\n" + "hp: " + str(block.hp)
	
	# Liquid Storage
	if block is LiquidStorage:
		textlabel.text += ("\n" + "%.2f" % block.stored + " mass " + block.liquid + " stored")
	_last_block = block

func show_tile(tilemap:TileMapLayer, qurey_pos:Vector2):
	visible = true
	var cell = tilemap.local_to_map(qurey_pos)
	var celldata = tilemap.get_celldata(cell)
	if celldata:
		var tile_info := TileDB.get_tile(celldata["tile_id"])
		var tile_name := str(tile_info.get("name", "unknown"))
		if tile_info["phase"] == "solid":
			textlabel.text = (
				tile_name + " tile\nHP:" + str(celldata["data"])
			)
		elif tile_info["phase"] == "liquid":
			var total_mass = tilemap.get_total_liquid_mass(tilemap.get_connected_liquid(cell))
			if total_mass < 1000.0:
				textlabel.text = (
					tile_name
					+ "\nTotal mass: "
					+ "%.f" % total_mass
					+ " kg"
				)
			else:
				textlabel.text = (
					tile_name
					+ "\nTotal mass: "
					+ "%.1f" % (total_mass / 1000)
					+ " T"
				)
# Clear the optional detail grid.
func _clear_grid() -> void:
	for c in grid_container.get_children():
		c.queue_free()
	grid_container.visible = false


func update_panel_size() -> void:
	var text_size: Vector2 = textlabel.get_size()
	var grid_size: Vector2 = Vector2.ZERO
	if grid_container.visible:
		grid_size = grid_container.get_size()

	var content_width = max(text_size.x, grid_size.x)
	var content_height = text_size.y
	if grid_container.visible:
		content_height += grid_size.y

	size = Vector2(content_width, content_height) + padding
