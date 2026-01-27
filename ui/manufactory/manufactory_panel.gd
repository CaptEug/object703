extends FloatingPanel

var manufactory:Manufactory

func _ready() -> void:
	$Label.text = manufactory.block_name
