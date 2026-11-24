class_name InventoryComponent
extends Node

@onready var inventory_panel: GridInventoryPanel = $InventoryLayer/GridInventoryPanel
@onready var inventory: GridInventory = $Inventory
@onready var inventory_layer: CanvasLayer = $InventoryLayer
@onready var item_hold_component: ItemHoldComponent = get_parent().get_node("ItemHoldComponent") as ItemHoldComponent

func _ready() -> void:
	inventory_panel.request_transfer_to.connect(_on_request_transfer_to)


func _unhandled_input(event: InputEvent) -> void:

	if event.is_action_pressed("inventory_drop"):
		if inventory_layer.visible:
			drop_item()
		elif not inventory_layer.visible:
			item_hold_component.unhold_item()

		get_viewport().set_input_as_handled()
		return

	if not inventory_layer.visible:
		return


	if event.is_action_pressed("inventory_rotate"):
		rotate_item()
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("inventory_hold"):
		hold_item()
		get_viewport().set_input_as_handled()




func _on_request_transfer_to(
	origin_inventory: GridInventory,
	origin_position: Vector2i,
	destination_inventory: GridInventory,
	destination_position: Vector2i,
	amount: int,
	is_rotated: bool
) -> void:
	if origin_inventory == null or destination_inventory == null:
		return

	if origin_inventory.database == null or origin_inventory.database != destination_inventory.database:
		return

	var source_stack: ItemStack = origin_inventory.get_stack_at(origin_position)
	if source_stack == null:
		return

	var definition: ItemDefinition = origin_inventory.database.get_item(source_stack.item_id)
	if definition == null:
		return

	var target_size: Vector2i = definition.size
	if is_rotated:
		target_size = Vector2i(target_size.y, target_size.x)

	var target_rect := Rect2i(destination_position, target_size)
	var destination_bounds := Rect2i(Vector2i.ZERO, destination_inventory.size)

	# Не передаём плагину размещение за пределами сетки.
	if not destination_bounds.encloses(target_rect):
		return

	var source_is_rotated := origin_inventory.is_stack_rotated(source_stack)

	if (
		origin_inventory == destination_inventory
		and origin_position == destination_position
		and source_is_rotated == is_rotated
	):
		return

	# В Inventory System 2.13.0 swap_stacks() сбрасывает поворот обоих стеков
	# и не проверяет результат повторного добавления. Не даём ему менять
	# пересекающиеся предметы, если хотя бы один из них повёрнут.
	for other_stack in destination_inventory.get_stacks_under(target_rect):
		if origin_inventory == destination_inventory and other_stack == source_stack:
			continue

		if (
			is_rotated
			or source_is_rotated
			or destination_inventory.is_stack_rotated(other_stack)
		):
			return

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

func remoove_item(item_id: String, amount: int) -> int:
	return inventory.remove(item_id, amount)

#даёт значение properties
func get_item_properties(item_id: String, properties: String) -> String:
	var definition = inventory.database.get_item(item_id)

	if definition == null:
		return ""

	return str(definition.properties.get(properties, ""))

#возвращает состояние видимости инвентаря
func is_inventory_open() -> bool:
	return inventory_layer.visible

#переключает состояние видимости инвентаря
func toggle_inventory() -> bool:
	inventory_layer.visible = not inventory_layer.visible
	return inventory_layer.visible

#кладёт предмет из инвентаря в руки
func hold_item() -> void:
	var dragged := GridDraggableElementUI.get_grabbed_dragable() as GridItemStackUI

	if dragged == null or not is_instance_valid(dragged.stack):
		return

	var id: String = dragged.stack.item_id

	var properties: Dictionary = dragged.stack.properties.duplicate(true)
	get_viewport().gui_cancel_drag()

	if not item_hold_component.hold_item(id, 1, properties):
		return
	remoove_item(id, 1)
