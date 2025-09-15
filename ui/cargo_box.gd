extends TextureRect

signal select(state, box_node)

var has_item = false

func _ready():
	_connet_signals()

func _on_mouse_entered():
	select.emit(true, self)

func _on_mouse_exited():
	select.emit(false, self)

func _connet_signals():
	select.connect(get_parent()._on_box_select)
	mouse_entered.connect(self._on_mouse_entered)
	mouse_exited.connect(self._on_mouse_exited)

func increase_item(item, num):
	assert(false, "This method must be overriden.")
	
func remove_item(item, num):
	assert(false, "This method must be overriden.")

func add_item(item):
	add_child(item)
	has_item = true

func reduce_item(num):
	var item = get_children()[0]
	var Quantity = item.Quantity
	Quantity -= num
	if Quantity <= 0:
		item.visible = false

func restore_item():
	var item = get_children()[0]
	item.visible = true
	
func clean():
	var item = get_children()[0]
	remove_child(item)
	has_item = false
	
func store(item):
	add_child(item)
	item.refresh()
	has_item = true
