extends Panel

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

func _ready():
	camera = get_tree().current_scene.find_child("Camera2D") as Camera2D


func _process(delta):
	time += delta
	if selected_vehicle:
		visible = true
		var color = Color.RED if selected_vehicle.destroyed else Color.GREEN
		var blink_strength = 0.75 + 0.25 * sin(time * 4.0)
		$Namelabel.add_theme_color_override("font_color", color)
		$Namelabel.text = selected_vehicle.vehicle_name
		$Offlinelabel.visible = selected_vehicle.destroyed
		$Offlinelabel.add_theme_color_override("font_color", color*blink_strength)
		retrieve_vehicle_data()
		
		#update cursor and cam
		if selected_vehicle.control.get_method() == "manual_control":
			camera.focus_on_vehicle(selected_vehicle, true)
		else:
			camera.target_rot = 0.0
		
		queue_redraw()
	else:
		visible = false

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
	
	var grid = selected_vehicle.grid
	grid = find_grid(grid)
	var vehicle_size = selected_vehicle.vehicle_size
	var grid_size = 16
	var draw_pos = $Marker2D.position - Vector2(vehicle_size/2) * grid_size
	var blocks = []
	for pos in grid:
		if is_instance_valid(grid[pos]) and not blocks.has(grid[pos]):
			blocks.append(grid[pos])
			var health_ratio = grid[pos].current_hp/grid[pos].HITPOINT
			var line_color = health_gradient.sample(clamp(health_ratio, 0.0, 1.0))
			# If health is not full, make it pulse
			if health_ratio < 1.0:
				var blink_strength = 0.75 + 0.25 * sin(time * 4.0)  # range from 0 to 1
				line_color = line_color * blink_strength
			# draw outline if the block has one
			if "outline_tex" in grid[pos]:
				var mask_tex = grid[pos].outline_tex
				draw_texture(mask_tex, draw_pos + Vector2(pos) * grid_size, line_color)
				continue
			# else only draw the shape
			var collisionshape := grid[pos].find_child("CollisionShape2D") as CollisionShape2D
			if collisionshape and collisionshape.shape is RectangleShape2D:
				var extents = collisionshape.shape.extents - Vector2(line_width,line_width)/2
				var rect = Rect2(draw_pos + Vector2(pos) * grid_size + Vector2(line_width,line_width)/2, extents * 2)
				draw_rect(rect, line_color, false, line_width)


func _on_controlbutton_pressed():
	current_mode = (current_mode + 1) % control_modes.size()
	selected_vehicle.control = control_modes[current_mode]
	
	# return idle if any other vehicle enter manual mode
	if selected_vehicle.control.get_method() == "manual_control":
		for vehicle in get_tree().get_nodes_in_group("vehicles"):
			if vehicle != selected_vehicle:
				if vehicle.control.get_method() == "manual_control":
					vehicle.control = Callable()


func find_grid(grid):
	var min_x:int
	var min_y:int
	var max_x:int
	var max_y:int
	
	for grid_pos in grid:
		min_x = grid_pos.x
		min_y = grid_pos.y
		max_x = grid_pos.x
		max_y = grid_pos.y
		break
	
	for grid_pos in grid:
		if min_x > grid_pos.x:
			min_x = grid_pos.x
		if min_y > grid_pos.y:
			min_y = grid_pos.y
		if max_x < grid_pos.x:
			max_x = grid_pos.x
		if max_y < grid_pos.y:
			max_y = grid_pos.y
	var grid_new = {}
	for pos in grid:
		var block:Block = grid[pos]
		pos = Vector2i(pos.x - min_x, pos.y - min_y)
		grid_new[pos] = block
	grid = grid_new
	return grid
