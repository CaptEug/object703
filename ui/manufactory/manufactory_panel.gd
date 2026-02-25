extends FloatingPanel

var manufactory:Manufactory

func _ready() -> void:
	$Label.text = manufactory.block_name


func _on_texture_button_pressed():
	queue_free()
