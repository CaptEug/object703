extends Node

var items = {
	"scrap": {
		"weight": 100,
		"icon": preload("res://assets/icons/items/scrap.png"),
		"max_stack": 999,
	},
	
	"metal": {
		"weight": 100,
		"icon": preload("res://assets/icons/items/metal.png"),
		"max_stack": 999,
	},
	
	"gas": {
		"weight": 10,
		"icon": preload("res://assets/icons/items/gas.png"),
		"max_stack": 999,
	},
	
	"57mmAP": {
		"weight": 4,
		"icon": preload("res://assets/icons/items/ap57mm.png"),
		"max_stack": 999,
		"shell_scene": preload("res://blocks/firepower/shells/ap_57_mm.tscn")
	},
	
	"PZGR75": {
		"weight": 7,
		"icon": preload("res://assets/icons/items/pzgr75.png"),
		"max_stack": 999,
		"shell_scene": preload("res://blocks/firepower/shells/pzgr_75.tscn")
	},
	
	"122mmAPHE": {
		"weight": 25,
		"icon": preload("res://assets/icons/items/aphe122mm.png"),
		"max_stack": 999,
		"shell_scene": preload("res://blocks/firepower/shells/aphe_122_mm.tscn")
	},
	
	"380mmrocket": {
		"weight": 350,
		"icon": preload("res://assets/icons/items/rocket380mm.png"),
		"max_stack": 999,
		"shell_scene": preload("res://blocks/firepower/shells/rocket_380_mm.tscn")
	},
}

func get_item(id: String) -> Dictionary:
	if items.has(id):
		return items[id]
	return {}
