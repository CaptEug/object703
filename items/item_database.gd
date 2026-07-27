extends Node

enum ItemType {
	MINERAL,
	MATERIAL,
	LIQUID,
}

enum ItemSubclass {
	RAW_ORE,
	AMMO,
	FUEL,
}

var items := {
	"scrap": {
		"name": "Scrap",
		"type": ItemType.MATERIAL,
		"subclasses": [],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/scrap.png"),
	},
	"metal": {
		"name": "Metal",
		"type": ItemType.MATERIAL,
		"subclasses": [],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/metal.png"),
	},
	"sandstone": {
		"name": "Sandstone",
		"type": ItemType.MINERAL,
		"subclasses": [],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/sandstone.png"),
	},
	"hematite": {
		"name": "Hematite",
		"type": ItemType.MINERAL,
		"subclasses": [ItemSubclass.RAW_ORE],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/hematite.png"),
	},
	"coal": {
		"name": "Coal",
		"type": ItemType.MINERAL,
		"subclasses": [ItemSubclass.FUEL],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/coal.png"),
	},
	"crude_oil": {
		"name": "Crude Oil",
		"type": ItemType.LIQUID,
		"subclasses": [],
		"icon": preload("res://assets/icons/items/crude_oil.png"),
	},
	"petroleum": {
		"name": "Petroleum",
		"type": ItemType.LIQUID,
		"subclasses": [ItemSubclass.FUEL],
		"icon": preload("res://assets/icons/items/petroleum.png"),
	},
	"PZGR88mm": {
		"name": "PzGr. 88 mm",
		"type": ItemType.MATERIAL,
		"subclasses": [ItemSubclass.AMMO],
		"weight": 7.0,
		"icon": preload("res://assets/icons/items/pzgr75.png"),
		"max_stack": 999,
		"shell_scene": preload("res://items/shells/ger/pzgr_88mm.tscn"),
	},
}

func get_item(item_id: String) -> Dictionary:
	return items.get(item_id, {})

func get_display_name(item_id: String) -> String:
	return get_item(item_id).get("name", item_id)

func get_items_by_type(item_type: int) -> Array[String]:
	var result: Array[String] = []
	for item_id: String in items:
		if items[item_id].get("type", -1) == item_type:
			result.append(item_id)
	result.sort()
	return result

func has_subclass(item_id: String, subclass: int) -> bool:
	var subclasses: Array = get_item(item_id).get("subclasses", [])
	return subclasses.has(subclass)
