extends FloatingPanel


var current_interface:Panel
var prev_interface:Panel
var next_interaface:Panel
@onready var world_selection = $MarginContainer/WorldSelection
@onready var world_generation = $MarginContainer/WorldGeneration


func _ready():
	current_interface = world_selection


func _on_back_button_pressed() -> void:
	if current_interface == world_selection:
		visible = false
	else:
		switch_interface(prev_interface)


func _on_foward_button_pressed():
	pass # Replace with function body.


func _on_new_world_button_pressed():
	switch_interface(world_generation)


func switch_interface(interface:Panel):
	prev_interface = current_interface
	current_interface.hide()
	current_interface = interface
	current_interface.show()
	
