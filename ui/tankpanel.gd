extends Panel

@onready var fuel_progressbar = $Fuel
@onready var ammo_progressbar = $Ammo
var selected_vehicle:Vehicle


func _ready():
	pass
		

func _process(delta):
	if selected_vehicle:
		visible = true
		$RichTextLabel.text = selected_vehicle.vehicle_name
		retrieve_vehicle_data()
		queue_redraw()
	else:
		visible = false

func _draw():
	if selected_vehicle:
		draw_grid()

func retrieve_vehicle_data():
	fuel_progressbar.max_value = selected_vehicle.get_fuel_cap()
	fuel_progressbar.value = selected_vehicle.update_current_fuel()
	ammo_progressbar.max_value = selected_vehicle.get_ammo_cap()
	ammo_progressbar.value = selected_vehicle.update_current_ammo()

func draw_grid():
	var line_color = Color(0, 0.7, 0)
	var line_width: float = 2.0
	var grid_size = 16
	var grid = selected_vehicle.grid
	var blocks = []
	for pos in grid:
		if not blocks.has(grid[pos]):
			blocks.append(grid[pos])
			# draw outline if the block has one
			if grid[pos].outline_tex:
				var mask_tex = grid[pos].outline_tex
				draw_texture(mask_tex, Vector2(pos) * grid_size, line_color)
				continue
			var collisionshape := grid[pos].find_child("CollisionShape2D") as CollisionShape2D
			if collisionshape and collisionshape.shape is RectangleShape2D:
				var extents = collisionshape.shape.extents
				var rect = Rect2(Vector2(pos) * grid_size, extents * 2)
				draw_rect(rect, line_color, false, line_width)
