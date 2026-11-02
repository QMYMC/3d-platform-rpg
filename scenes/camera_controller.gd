extends Node3D

var min_limit_x = -0.8
var max_limit_x = -0.2
var mouse_acceleration: = 0.005
var horizontal_acceleration: = 2.0
var vertical_acceleration: = 1.0
var pending_mouse_motion := Vector2.ZERO

func _physics_process(_delta: float) -> void:
	var joy_dir = Input.get_vector("pan_left","pan_right","pan_up","pan_down")
	rotate_from_vector(joy_dir)
	rotate_from_vector(pending_mouse_motion)
	pending_mouse_motion = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		pending_mouse_motion += event.relative * mouse_acceleration
		
func rotate_from_vector(v: Vector2):
	if v.length() > 0:
		rotation.y -= v.x
		rotation.x -= v.y
		rotation.x = clamp(rotation.x, min_limit_x, max_limit_x)
