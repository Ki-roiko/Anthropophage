extends Node

@onready var inventory: GridInventory = $"../Inventory"
@onready var inventory_panel: GridInventoryPanel = $"../InventoryLayer/GridInventoryPanel"

func _ready() -> void:
	inventory_panel.request_transfer_to.connect(_on_request_transfer_to)
	inventory.add("bandage", 1)
	inventory.add("scrap", 1)
	inventory.add("toolbox", 1)

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
