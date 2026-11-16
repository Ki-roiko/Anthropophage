extends Node

@onready var inventory: GridInventory = $"../Inventory"
@onready var drop_point: Marker3D = $"../../Head/DropPoint"


func _ready() -> void:
	inventory.request_drop_item.connect(item_dropper)


func item_dropper(id: String, amount: int, properties: Dictionary) -> void:
	if amount <= 0:
		return

	var definition = inventory.database.get_item(id)
	if definition == null:
		push_warning("Cannot drop item '%s': definition was not found." % id)
		return

	var path: String = str(definition.properties.get("dropped_item", ""))
	if path.is_empty():
		push_warning("Cannot drop item '%s': dropped_item is not configured." % id)
		return

	var packed_scene := load(path) as PackedScene
	if packed_scene == null:
		push_error("Cannot load dropped item scene: %s" % path)
		return

	var item := packed_scene.instantiate() as WorldItem
	if item == null:
		push_error("Dropped item scene does not have a WorldItem root: %s" % path)
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		item.free()
		push_error("Cannot drop item: current scene is null.")
		return

	item.item_id = id
	item.item_properties = properties
	scene_root.add_child(item)
	item.global_transform = drop_point.global_transform
