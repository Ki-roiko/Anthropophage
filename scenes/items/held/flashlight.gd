extends Node3D

var id: String = "flashlight"
var properties: Dictionary
@onready var light : SpotLight3D = $SpotLight3D

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory_rotate"):
		toggle_light()


func toggle_light() -> bool:
	light.visible = not light.visible
	return light.visible
