extends Node

var items = {
	"scrap": {
		"weight": 100,
		"icon": preload("res://assets/icons/scrap.png"),
		"max_stack": 999,
	},
	
	"metal": {
		"weight": 100,
		"icon": preload("res://assets/icons/metal.png"),
		"max_stack": 999,
	},
	
	"gas": {
		"weight": 10,
		"icon": preload("res://assets/icons/gas.png"),
		"max_stack": 999,
	},
	
	"57mmAP": {
		"weight": 4,
		"icon": preload("res://assets/icons/metal.png"),
		"max_stack": 999,
		"shell_scene": preload("res://blocks/firepower/shells/ap_57_mm.tscn")
	},
}

func get_item(id: String) -> Dictionary:
	if items.has(id):
		return items[id]
	return {}
