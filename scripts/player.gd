extends CharacterBody3D

@export_group("Moving")
@export var mouse_sensitivity : float = 0.002
@export var speed : float = 5.0
@export var sprint_speed : float = 16.0
@export var gravity : float = 9.8
@export var jump_velocity : float = 4.5

@onready var head : Node3D = $Head

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_look(event)

func _physics_process(delta: float) -> void:
	moving(delta)










func moving(delta: float) -> void:
	var input_dir : Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	var current_speed = speed
	if Input.is_action_pressed("sprint"):
		current_speed = sprint_speed
	
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed
	
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	move_and_slide()

func mouse_look(event: InputEventMouseMotion) -> void:
	rotate_y(-event.relative.x * mouse_sensitivity)
	head.rotate_x(-event.relative.y * mouse_sensitivity)
	head.rotation.x = clampf(head.rotation.x, -PI/2, PI/2)
