class_name HudComponent extends Node

@onready var inventory_component: InventoryComponent = get_parent().get_node("InventoryComponent")
@onready var player: CharacterBody3D = get_parent()
@onready var hud_layer: CanvasLayer = $HudLayer

func _unhandled_input(event: InputEvent) -> void:
	
	if event.is_action_pressed("inventory_open"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()
		return
	if inventory_component.inventory_layer.visible:
		return
	
	
	if event is InputEventMouseMotion:
		player.mouse_look(event)



func _toggle_inventory() -> void:
	inventory_component.inventory_layer.visible = not inventory_component.inventory_layer.visible
	hud_layer.visible = not hud_layer.visible
	
	if inventory_component.inventory_layer.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
