extends Control

var time:String = "00:00"

func _process(delta):
	$Panel/Clock.text = time
