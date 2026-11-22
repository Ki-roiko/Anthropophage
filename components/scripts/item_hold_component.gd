class_name ItemHoldComponent
extends Node

@onready var inventory_component: InventoryComponent = get_parent().get_node("InventoryComponent") as InventoryComponent
@onready var holding_point: Marker3D = get_node("../Head/Camera3D/HoldingPoint")

func hold_item(id: String, amount: int, properties) -> bool:

	if not holding_point.get_child(0):

		var path := inventory_component.get_item_scene_path(id, "holding_item")
		var packed_scene := load(path) as PackedScene
		var item := packed_scene.instantiate()
		item.properties = properties
		holding_point.add_child(item)
		item.transform = Transform3D.IDENTITY
		item.global_transform = holding_point.global_transform
		return true
	else:

		var holding = holding_point.get_child(0)
		var remaining := inventory_component.add_item(holding.id, 1, holding.properties)
		if remaining != 0:
			return false
		holding.queue_free()
		
		var path := inventory_component.get_item_scene_path(id, "holding_item")
		var packed_scene := load(path) as PackedScene
		var item := packed_scene.instantiate()
		item.item_properties = properties
		holding_point.add_child(item)
		item.transform = Transform3D.IDENTITY
		item.global_transform = holding_point.global_transform
		return true

func unhold_item() -> bool:

	var holding = holding_point.get_child(0)
	if inventory_component.add_item(holding.id, 1, holding.properties) >= 1:
		holding.queue_free()
		return true
	else:
		return false
