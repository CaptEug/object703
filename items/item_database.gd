extends Node

var items = {
	### Material ###
	"scrap": {
		"type": "solid",
		"weight": 100,
		"icon": preload("res://assets/icons/items/scrap.png"),
		"max_stack": 999,
	},
	
	"metal": {
		"type": "solid",
		"weight": 100,
		"icon": preload("res://assets/icons/items/metal.png"),
		"max_stack": 999,
	},
	
	"sandstone": {
		"type": "solid",
		"weight": 100,
		"icon": preload("res://assets/icons/items/sandstone.png"),
		"max_stack": 999,
	},
	
	"hematite": {
		"type": "solid",
		"weight": 100,
		"icon": preload("res://assets/icons/items/hematite.png"),
		"max_stack": 999,
	},
	
	"coal": {
		"type": "solid",
		"weight": 100,
		"icon": preload("res://assets/icons/items/coal.png"),
		"max_stack": 999,
	},
	
	### Liquid ###
	
	"crude_oil": {
		"type": "liquid",
		"icon": preload("res://assets/icons/items/crude_oil.png"),
	},
	
	"petroleum": {
		"type": "liquid",
		"icon": preload("res://assets/icons/items/petroleum.png"),
	},
	
	### AMMO ###
	
	"PZGR88mm": {
		"type": "ammo",
		"weight": 7,
		"icon": preload("res://assets/icons/items/pzgr75.png"),
		"max_stack": 999,
		"shell_scene": preload("res://items/shells/ger/pzgr_88mm.tscn")
	},
}

func get_item(id: String) -> Dictionary:
	if items.has(id):
		return items[id]
	return {}
