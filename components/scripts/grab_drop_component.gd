class_name GrabDropComponent
extends Node3D

@onready var ray: RayCast3D = $RayCast3D
@onready var inventory_component: InventoryComponent = $InventoryComponent


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory_interact"):
		grab_item()
	
	if event.is_action_pressed("inventory_drop"):
		drop_item()

func drop_item() -> void:
	var dragged := GridDraggableElementUI.get_grabbed_dragable() as GridItemStackUI

	if dragged == null or not is_instance_valid(dragged.stack):
		return

	var stack_index: int = inventory_component.stacks.find(dragged.stack)
	if stack_index == -1:
		return

	var properties: Dictionary = dragged.stack.properties.duplicate(true)
	get_viewport().gui_cancel_drag()
	inventory_component.drop_from_inventory(stack_index, 1, properties)

func grab_item():
	if ray.is_colliding():
		var grabbing_item = ray.get_collider()
		if grabbing_item is WorldItem:
			if not inventory_component.add_item(grabbing_item.item_id, 1, grabbing_item.item_properties): 
				grabbing_item.queue_free()
