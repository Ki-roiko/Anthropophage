class_name GrabDropComponent
extends Node3D

@onready var ray: RayCast3D = $RayCast3D
@onready var inventory_component: InventoryComponent = get_parent().get_node("InventoryComponent") as InventoryComponent
@onready var drop_point: Marker3D = $DropPoint

func _ready() -> void:
	inventory_component.inventory.request_drop_item.connect(item_dropper)


func _unhandled_input(event: InputEvent) -> void:
	if inventory_component.is_inventory_open():
		return

	if event.is_action_pressed("inventory_interact"):
		grab_item()
		get_viewport().set_input_as_handled()





func grab_item():
	if ray.is_colliding():
		var grabbing_item = ray.get_collider()
		if grabbing_item is WorldItem:
			if inventory_component.add_item(grabbing_item.item_id, 1, grabbing_item.item_properties) == 0:
				grabbing_item.queue_free()



func item_dropper(id: String, amount: int, properties: Dictionary) -> void:
	if amount <= 0:
		return

	var path := inventory_component.get_item_scene_path(id, "dropped_item")
	if path.is_empty():
		push_warning("Cannot find dropped item scene for '%s'." % id)
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
