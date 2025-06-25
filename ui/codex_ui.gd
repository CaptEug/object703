extends Control

@onready var tree = $Tree

# Called when the node enters the scene tree for the first time.
func _ready():
	var root = tree.create_item()
	root.set_text(0, "Blocks")
	
	# block type
	var weapon = tree.create_item(root)
	weapon.set_text(0, "Weapon")
	var power = tree.create_item(root)
	power.set_text(0, "Power")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
