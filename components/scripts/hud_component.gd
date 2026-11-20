class_name HudComponent extends Node

@onready var inventory_component: InventoryComponent = get_parent().get_node("InventoryComponent")
@onready var hud_layer: CanvasLayer = $HudLayer

func _ready() -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	
	if event.is_action_pressed("inventory_open"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()
		return
	if inventory_component.inventory_layer.visible:
		return




func _toggle_inventory() -> void:
	var is_open := inventory_component.toggle_inventory()
	hud_layer.visible = not is_open

	if is_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
