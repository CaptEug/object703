class_name Block
extends RigidBody2D

var current_hp:int
var weight: float
var block_name: String
var type:String
var size: Vector2
var parent_vehicle: Vehicle = null  
var _cached_icon: Texture2D
var description:String

signal frame_post_drawn

func _ready():
	RenderingServer.frame_post_draw.connect(_emit_relay_signal)
	init()
	mass = weight
	parent_vehicle = get_parent() as Vehicle
	if parent_vehicle:
		parent_vehicle._add_block(self)
	pass # Replace with function body.

func init():
	pass

func _emit_relay_signal():
	frame_post_drawn.emit()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass


func damage(amount:int):
	print(str(name)+'receive damage:'+str(amount))
	current_hp -= amount
	if current_hp <= 0:
		if parent_vehicle:
			parent_vehicle.remove_block(self)
		queue_free()
		
func get_icon_texture():
	var texture_blocks = find_child("Sprite2D")
	if texture_blocks != null and texture_blocks is Sprite2D:
		return texture_blocks.texture
	return null

	

func get_block_info() -> Dictionary:
	init()
	mass = weight
	return {
		"name": block_name,
		"hitpoint": current_hp,
		"weight": weight,
		"size": size,
		"icon": get_icon_texture(),
		"type": _get_block_type(),
		"description": description
	}

func _get_block_type() -> String:
	if self is Weapon:
		return "Weapon"
	elif self is Powerpack:
		return "Power"
	else:
		return "Armor"
