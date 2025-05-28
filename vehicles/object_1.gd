extends Vehicle


# Called when the node enters the scene tree for the first time.
func _ready():
	for block in get_children():
		blocks.append(block)
		if block is Track:
			tracks.append(block)
		if block is Powerpack:
			powerpacks.append(block)
	super._ready()
	total_power = self.get_total_engine_power()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	super._process(delta)
	pass
