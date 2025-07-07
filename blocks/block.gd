class_name Block
extends RigidBody2D

var current_hp:int
var weight: float
var block_name: String
var type:String
var size: Vector2i
var parent_vehicle: Vehicle = null  
var _cached_icon: Texture2D
var neighbors:= {}
var global_grid_pos:= []

signal frame_post_drawn

func _ready():
	RenderingServer.frame_post_draw.connect(_emit_relay_signal)
	mass = weight
	parent_vehicle = get_parent() as Vehicle
	pass # Replace with function body.


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
