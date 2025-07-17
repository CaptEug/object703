extends Panel

@onready var fuel_progressbar = $Fuel
@onready var ammo_progressbar = $Ammo
@export var health_gradient: Gradient  # Set this from the Inspector
var time:float = 0
var selected_vehicle:Vehicle


func _ready():
	pass


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
		queue_redraw()
	else:
		visible = false

func _draw():
	if selected_vehicle:
		draw_grid()

func retrieve_vehicle_data():
	fuel_progressbar.max_value = selected_vehicle.get_fuel_cap()
	fuel_progressbar.value = selected_vehicle.get_current_fuel()
	ammo_progressbar.max_value = selected_vehicle.get_ammo_cap()
	ammo_progressbar.value = selected_vehicle.get_current_ammo()

func draw_grid():
	var line_width: float = 2.0
	
	var grid = selected_vehicle.grid
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
			if grid[pos].outline_tex:
				var mask_tex = grid[pos].outline_tex
				draw_texture(mask_tex, draw_pos + Vector2(pos) * grid_size, line_color)
				continue
			# else only draw the shape
			var collisionshape := grid[pos].find_child("CollisionShape2D") as CollisionShape2D
			if collisionshape and collisionshape.shape is RectangleShape2D:
				var extents = collisionshape.shape.extents - Vector2(line_width,line_width)/2
				var rect = Rect2(draw_pos + Vector2(pos) * grid_size + Vector2(line_width,line_width)/2, extents * 2)
				draw_rect(rect, line_color, false, line_width)
