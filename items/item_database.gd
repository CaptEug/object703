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
	
	#"57mmAP": {
		#"type": "ammo",
		#"weight": 4,
		#"icon": preload("res://assets/icons/items/ap57mm.png"),
		#"max_stack": 999,
		#"shell_scene": preload("res://blocks/firepower/shells/ap_57_mm.tscn")
	#},
	#
	#"PZGR75": {
		#"type": "ammo",
		#"weight": 7,
		#"icon": preload("res://assets/icons/items/pzgr75.png"),
		#"max_stack": 999,
		#"shell_scene": preload("res://blocks/firepower/shells/pzgr_75.tscn")
	#},
	
	"PZGR88mm": {
		"type": "ammo",
		"weight": 7,
		"icon": preload("res://assets/icons/items/pzgr75.png"),
		"max_stack": 999,
		"shell_scene": preload("res://items/shells/ger/pzgr_88mm.tscn")
	},
	
	#"122mmAPHE": {
		#"type": "ammo",
		#"weight": 25,
		#"icon": preload("res://assets/icons/items/aphe122mm.png"),
		#"max_stack": 999,
		#"shell_scene": preload("res://blocks/firepower/shells/aphe_122_mm.tscn")
	#},
	#
	#"122mmHE": {
		#"type": "ammo",
		#"weight": 25,
		#"icon": preload("res://assets/icons/items/he122mm.png"),
		#"max_stack": 999,
		#"shell_scene": preload("res://blocks/firepower/shells/aphe_122_mm.tscn")
	#},
	#
	#"380mmrocket": {
		#"type": "ammo",
		#"weight": 350,
		#"icon": preload("res://assets/icons/items/rocket380mm.png"),
		#"max_stack": 999,
		#"shell_scene": preload("res://blocks/firepower/shells/rocket_380_mm.tscn")
	#},
}

func get_item(id: String) -> Dictionary:
	if items.has(id):
		return items[id]
	return {}
