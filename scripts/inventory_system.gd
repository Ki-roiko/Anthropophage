extends Node

@onready var inventory_panel: GridInventoryPanel = $InventoryLayer/GridInventoryPanel
@onready var inventory: GridInventory = $Inventory
@onready var inventory_layer: CanvasLayer = $InventoryLayer


func _ready() -> void:
	inventory_panel.request_transfer_to.connect(_on_request_transfer_to)
	

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory_rotate") and  inventory_layer.visible:
		rotate_item()

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
	var selected = inventory_panel.grid_inventory_ui.get_selected_stacks()
		
	if not selected.is_empty():
		
		for item in selected:
			var stack = selected[item].stack
			
			if inventory.has_stack(stack):
				inventory.rotate(stack)
