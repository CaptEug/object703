extends Panel


@onready var textlabel = $RichTextLabel
var selected_block:Block

func _ready():
	pass

func _process(delta):
	size = textlabel.size + Vector2(16,16)

func _physics_process(delta):
	var mouse_pos = get_tree().current_scene.get_local_mouse_position()
	var space_state = get_world_2d().direct_space_state

	var query := PhysicsPointQueryParameters2D.new()
	query.position = mouse_pos
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var results = space_state.intersect_point(query)
	if results.size() > 0:
		var body = results[0].collider
		if body is Block:
			visible = true
			
			var vehicle = body.get_parent_vehicle() as Vehicle
			if vehicle:
				textlabel.text = body.block_name + "  from  " + vehicle.vehicle_name
			else:
				textlabel.text = body.block_name + ": debris"
			global_position = get_viewport().get_mouse_position() + Vector2(16, 16)
	else:
		visible = false
