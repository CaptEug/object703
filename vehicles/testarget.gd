extends Vehicle


# Called when the node enters the scene tree for the first time.
func _ready():
	for block in get_children():
		blocks.append(block)
	super._ready()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass
