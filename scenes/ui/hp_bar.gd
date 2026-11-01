@tool
extends TextureRect

const ANIMATION_TIME: float = 0.5

@export var min_value: float = 0.0
@export var max_value: float = 100.0
@export var value: float = 0.0

@onready var progress_shader: ShaderMaterial = $HBoxContainer/ProgressTextureRect.material as ShaderMaterial

var _tween: Tween


func _ready() -> void:
	update_texture(0.0)


func set_value(new_value: float, animate: bool = true) -> void:
	var clamped_value := clampf(new_value, min_value, max_value)
	var direction := signf(clamped_value - value)
	value = clamped_value

	if progress_shader:
		update_texture(direction if animate else 0.0)


func update_texture(direction: float) -> void:
	if not progress_shader:
		return

	var value_range := max_value - min_value
	if value_range <= 0.0:
		push_warning("StatBar: max_value must be greater than min_value.")
		return

	var progress := clampf((value - min_value) / value_range, 0.0, 1.0)

	if direction < 0.0:
		get_tween().tween_property(
			progress_shader,
			"shader_parameter/progress_tail",
			progress,
			ANIMATION_TIME
		)
		progress_shader.set_shader_parameter("progress", progress)
	elif direction > 0.0:
		get_tween().tween_property(
			progress_shader,
			"shader_parameter/progress",
			progress,
			ANIMATION_TIME
		)
		progress_shader.set_shader_parameter("progress_tail", progress)
	else:
		progress_shader.set_shader_parameter("progress", progress)
		progress_shader.set_shader_parameter("progress_tail", progress)


func get_tween() -> Tween:
	if _tween:
		_tween.kill()

	_tween = create_tween().set_ease(Tween.EASE_OUT)
	return _tween
