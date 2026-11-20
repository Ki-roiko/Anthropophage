class_name InventoryComponent
extends Node

@onready var inventory_panel: GridInventoryPanel = $InventoryLayer/GridInventoryPanel
@onready var inventory: GridInventory = $Inventory
@onready var inventory_layer: CanvasLayer = $InventoryLayer


func _ready() -> void:
	inventory_panel.request_transfer_to.connect(_on_request_transfer_to)


func _unhandled_input(event: InputEvent) -> void:
	if not inventory_layer.visible:
		return
	
	if event.is_action_pressed("inventory_rotate"):
		rotate_item()
		get_viewport().set_input_as_handled()


	


func _on_request_transfer_to(
	origin_inventory: GridInventory,
	origin_position: Vector2i,
	destination_inventory: GridInventory,
	destination_position: Vector2i,
	amount: int,
	is_rotated: bool
) -> void:
	origin_inventory.transfer_to(
		origin_position,
		destination_inventory,
		destination_position,
		amount,
		is_rotated
	)


func rotate_item() -> void:
	var dragged := GridDraggableElementUI.get_grabbed_dragable() as GridItemStackUI

	if dragged == null:
		return

	dragged.drag_is_rotated = !dragged.drag_is_rotated

	var preview := GridItemStackUI.active_drag_preview

	if is_instance_valid(preview):
		preview.set_visual_rotation(dragged.drag_is_rotated)


func drop_item() -> void:
	var dragged := GridDraggableElementUI.get_grabbed_dragable() as GridItemStackUI

	if dragged == null or not is_instance_valid(dragged.stack):
		return

	var stack_index: int = inventory.stacks.find(dragged.stack)
	if stack_index == -1:
		return

	var properties: Dictionary = dragged.stack.properties.duplicate(true)
	get_viewport().gui_cancel_drag()
	inventory.drop_from_inventory(stack_index, 1, properties)

func add_item(item_id: String, amount: int, properties: Dictionary) -> int:
	return inventory.add(item_id, amount, properties)