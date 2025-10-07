extends FloatingPanel

@onready var fuel_progressbar = $Fuel
@onready var ammo_progressbar = $Ammo
@export var health_gradient: Gradient  # Set this from the Inspector
var time:float = 0
var selected_vehicle:Vehicle
var camera:Camera2D
var control_modes := []
var current_mode := 0
var idle_icon:Texture = preload("res://assets/icons/idle.png")
var manual_icon:Texture = preload("res://assets/icons/driving_wheel.png")
var remote_icon:Texture = preload("res://assets/icons/remote_control.png")
var ai_icon:Texture = preload("res://assets/icons/ai.png")
var crosshair:Texture = preload("res://assets/icons/crosshair.png")
var exit_focus = true

func _ready():
	camera = get_tree().current_scene.find_child("Camera2D") as Camera2D


func _process(delta):
	time += delta
	if selected_vehicle:
		var color = Color.RED if selected_vehicle.destroyed else Color.GREEN
		var blink_strength = 0.75 + 0.25 * sin(time * 4.0)
		$Namelabel.add_theme_color_override("font_color", color)
		$Namelabel.text = selected_vehicle.vehicle_name
		$Offlinelabel.visible = selected_vehicle.destroyed
		$Offlinelabel.add_theme_color_override("font_color", color*blink_strength)
		retrieve_vehicle_data()
		
		#update cursor and cam
		if selected_vehicle.control.get_method() == "manual_control":
			camera.focus_on_vehicle(selected_vehicle)
			exit_focus = false
		else:
			if exit_focus == false:
				camera.target_rot = 0.0
				exit_focus = true
		
		queue_redraw()
	
	$CargoButton.visible = is_frontmost()
	$ModifyButton.visible = is_frontmost()
	
		

func _draw():
	if selected_vehicle:
		draw_grid()

func retrieve_vehicle_data():
	#get vehicle resource data
	fuel_progressbar.max_value = selected_vehicle.get_fuel_cap()
	fuel_progressbar.value = selected_vehicle.get_current_fuel()
	ammo_progressbar.max_value = selected_vehicle.get_ammo_cap()
	ammo_progressbar.value = selected_vehicle.get_current_ammo()
	#check vehicle control
	var available_modes := [Callable()]
	var button_icons := [idle_icon]
	if selected_vehicle.check_control("manual_control"):
		available_modes.append(selected_vehicle.check_control("manual_control"))
		button_icons.append(manual_icon)
	if selected_vehicle.check_control("remote_control"):
		available_modes.append(selected_vehicle.check_control("remote_control"))
		button_icons.append(remote_icon)
	if selected_vehicle.check_control("AI_control"):
		available_modes.append(selected_vehicle.check_control("AI_control"))
		button_icons.append(ai_icon)
	control_modes = available_modes
	current_mode = control_modes.find(selected_vehicle.control)
	$Controlbutton.texture_normal = button_icons[current_mode]

func draw_grid():
	var line_width: float = 2.0
	var result = normalize_grid(selected_vehicle.grid)
	var grid = result[0]
	var max_x = result[1]
	var max_y = result[2]
	var vehicle_size = selected_vehicle.vehicle_size
	var grid_size = 16
	var draw_pos = $Marker2D.position - Vector2(vehicle_size/2) * grid_size
	var blocks = []
	var check_blocks = []
	for pos in selected_vehicle.grid.keys():
		if not check_blocks.has(selected_vehicle.grid[pos]):
			check_blocks.append(selected_vehicle.grid[pos])
	if not has_commend_class_exact(check_blocks):
		return
	for x in max_x+1:
		for y in max_y+1:
			var pos = Vector2i(x, y)
			if not grid.has(pos):
				continue
			if is_instance_valid(grid[pos]) and not blocks.has(grid[pos]):
				blocks.append(grid[pos])
				var health_ratio = grid[pos].current_hp/grid[pos].HITPOINT
				var line_color = health_gradient.sample(clamp(health_ratio, 0.0, 1.0))
				var rot = grid[pos].base_rotation_degree
				var topleft = Vector2(pos) * grid_size
				var center = Vector2(grid[pos].size) * grid_size / 2
				
				# If health is not full, make it pulse
				if health_ratio < 1.0:
					var blink_strength = 0.75 + 0.25 * sin(time * 4.0)  # range from 0 to 1
					line_color = line_color * blink_strength
				
				# Apply rotation
				draw_set_transform(draw_pos + topleft + center, deg_to_rad(rot), Vector2.ONE)
				
				# draw outline if the block has one
				if "outline_tex" in grid[pos]:
					var mask_tex = grid[pos].outline_tex
					draw_texture(mask_tex, -mask_tex.get_size() / 2, line_color)
					continue
				
				# else only draw the shape
				
				var collisionshape := grid[pos].find_child("CollisionShape2D") as CollisionShape2D
				if collisionshape and collisionshape.shape is RectangleShape2D:
					var extents = collisionshape.shape.extents - Vector2(line_width,line_width)/2
					if rot == 90 or rot == -90:
						extents = Vector2(extents.y, extents.x)
					var rect = Rect2(Vector2(line_width,line_width)/2, extents * 2)
					draw_set_transform(draw_pos + topleft, 0, Vector2.ONE)
					draw_rect(rect, line_color, false, line_width)
					
				# Reset rotaion
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func has_commend_class_exact(check_blocks):
	for block in check_blocks:
		if block is Command:
			return true
	return false


func _on_controlbutton_pressed():
	current_mode = (current_mode + 1) % control_modes.size()
	selected_vehicle.control = control_modes[current_mode]
	
	# return idle if any other vehicle enter manual mode
	if selected_vehicle.control.get_method() == "manual_control":
		for vehicle in get_tree().get_nodes_in_group("vehicles"):
			if vehicle != selected_vehicle:
				if vehicle.control.get_method() == "manual_control":
					vehicle.control = Callable()


func normalize_grid(grid: Dictionary) -> Array:
	if grid.size() == 0:
		return [{}, 0, 0]

	var keys = grid.keys()
	var first = keys[0]
	var min_x = first.x
	var min_y = first.y
	var max_x = first.x
	var max_y = first.y

	# Find min/max
	for pos in keys:
		if pos.x < min_x:
			min_x = pos.x
		if pos.y < min_y:
			min_y = pos.y
		if pos.x > max_x:
			max_x = pos.x
		if pos.y > max_y:
			max_y = pos.y

	# Normalize positions
	var grid_new = {}
	for pos in keys:
		var block = grid[pos]
		var new_pos = Vector2i(pos.x - min_x, pos.y - min_y)
		grid_new[new_pos] = block

	return [grid_new, max_x - min_x, max_y - min_y]



func _on_close_button_pressed():
	visible = false

func is_frontmost() -> bool:
	var parent = get_parent()
	if parent == null:
		return true  # Root node is always "frontmost" by default
	return get_index() == parent.get_child_count() - 1
