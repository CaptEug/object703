class_name Block
extends RigidBody2D

var current_hp:float
var weight: float
var block_name: String
var type:String
var size: Vector2i
var parent_vehicle: Vehicle = null  
var _cached_icon: Texture2D
var neighbors:= {}
var connected_blocks := []
var global_grid_pos:= []
var mouse_inside:bool
var outline_tex:Texture

signal frame_post_drawn

func _ready():
	RenderingServer.frame_post_draw.connect(_emit_relay_signal)
	mass = weight
	parent_vehicle = get_parent() as Vehicle
	#initialize signal
	input_pickable = true
	connect("input_event", Callable(self, "_on_input_event"))
	connect("mouse_entered", Callable(self, "_on_mouse_entered"))
	connect("mouse_exited", Callable(self, "_on_mouse_exited"))

func _process(_delta):
	pass

func _emit_relay_signal():
	frame_post_drawn.emit()

func _on_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var control_ui := get_tree().current_scene.find_child("CanvasLayer") as CanvasLayer
			if control_ui:
				var tank_panel := control_ui.find_child("Tankpanel") as Panel
				tank_panel.selected_vehicle = parent_vehicle
			

func _on_mouse_entered():
	mouse_inside = true

func _on_mouse_exited():
	mouse_inside = false

func damage(amount:int):
	print(str(name)+' receive damage:'+str(amount))
	current_hp -= amount
	if current_hp <= 0:
		if parent_vehicle:
			parent_vehicle.remove_block(self)
		queue_free()

func get_icon_texture():
	var texture_blocks := find_child("Sprite2D") as Sprite2D
	return texture_blocks.texture

func get_neighors():
	neighbors.clear()
	if parent_vehicle:
		var grid = parent_vehicle.grid
		var grid_pos = parent_vehicle.find_pos(grid, self)
		for x in size.x:
			for y in size.y:
				var directions = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
				for dir in directions:
					var neighbor_pos = grid_pos + Vector2i(x, y) + dir
					if grid.has(neighbor_pos) and grid[neighbor_pos] != self:
						if is_instance_valid(grid[neighbor_pos]):
							var neighbor = grid[neighbor_pos]
							var neighbor_real_pos = parent_vehicle.find_pos(grid, neighbor)
							neighbors[neighbor_real_pos - grid_pos] = neighbor
	return neighbors

func get_all_connected_blocks():
	connected_blocks.clear()
	get_connected_blocks(self)
	return connected_blocks

func get_connected_blocks(block:Block):
	var nbrs = block.neighbors
	for neighbor in nbrs.values():
		if is_instance_valid(neighbor):
			if not connected_blocks.has(neighbor) and neighbor != self:
				connected_blocks.append(neighbor)
				get_connected_blocks(neighbor)
