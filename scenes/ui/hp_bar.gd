@tool
extends TextureRect

const ANIMATION_TIME: float = 0.5

@export var min_value: float = 0.0
@export var max_value: float = 100.0
@export var value: float = 0.0

@onready var progress_shader : ShaderMaterial = %ProgressTextureRect.material as ShaderMaterial

var _tween: Tween

func _ready() -> void:
	update_texture(0)

func set_value(new_value: float) -> void:
	var difference = new_value - value
	value = clampf(new_value, min_value, max_value)
	if progress_shader:
		update_texture(sign(difference))

func update_texture(direction: int) -> void:
	var progress = value / (max_value - min_value)
	
	if direction < 0:
		get_tween().tween_property(progress_shader, "shader_param/progress_tail", progress, 0.5)
		progress_shader.set_shader_param("shader_param/progress", progress)
	elif direction > 0:
		get_tween().tween_property(progress_shader, "shader_param/progress", progress, 0.5)
		progress_shader.set_shader_param("shader_param/progress_tail", progress)
	else:
		progress_shader.set_shader_param("progress", progress)
		progress_shader.set_shader_param("progress_tail", progress)



func get_tween() -> Tween:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT)
	return _tween
