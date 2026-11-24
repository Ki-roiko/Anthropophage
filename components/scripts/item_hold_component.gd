class_name ItemHoldComponent
extends Node

#Компонент взятия в руки и убирания из рук предмета

@onready var inventory_component: InventoryComponent = get_parent().get_node("InventoryComponent") as InventoryComponent
@onready var holding_point: Marker3D = get_node("../Head/Camera3D/HoldingPoint")

func hold_item(id: String, amount: int, properties) -> bool:

	#иф определяет есть ли уже предмет в руке
	if holding_point.get_child_count() == 0:
		#если предмета нету
		var path := inventory_component.get_item_properties(id, "holding_item")
		var packed_scene := load(path) as PackedScene
		if packed_scene:
			var item := packed_scene.instantiate()
			item.properties = properties
			holding_point.add_child(item)
			item.transform = Transform3D.IDENTITY
			item.global_transform = holding_point.global_transform
			return true
		else:
			return false
	else:
		#если предмет есть, он сначала помещается в инвентарь
		var holding = holding_point.get_child(0)
		var remaining := inventory_component.add_item(holding.id, 1, holding.properties)
		if remaining != 0:
			return false
		holding.queue_free()
		
		var path := inventory_component.get_item_properties(id, "holding_item")
		var packed_scene := load(path) as PackedScene
		if packed_scene:
			var item := packed_scene.instantiate()
			item.properties = properties
			holding_point.add_child(item)
			item.transform = Transform3D.IDENTITY
			item.global_transform = holding_point.global_transform
			return true
		else:
			return false

func unhold_item() -> bool:
	#убеирает предмет из руки 
	if holding_point.get_child_count() == 0:
		return false

	var holding = holding_point.get_child(0)

	if inventory_component.add_item(holding.id, 1, holding.properties) == 0:
		holding.queue_free()
		return true
	else:
		return false
