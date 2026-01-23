class_name Manufactory
extends Block

var connected_cargos: Array[Cargo]
var recipes: Array[Dictionary]
var input_inv: Array
var output_inv: Array

func _ready():
	pass


func _process(delta):
	pass

func find_recipe():
	for recipe in recipes:
		if recipe_can_run(recipe):
			return recipe

func recipe_can_run(recipe:Dictionary) -> bool:
	for item_id in recipe["inputs"]:
		if not has_material(item_id, recipe["inputs"][item_id]):
			return false
	return true

func has_material(item_id:String, amount:int):
	for cargo in connected_cargos:
		var inv = cargo.inventory
		for item in inv:
			if item == {}:
				continue
			if item["id"] == item_id:
				return item["count"] >= amount
