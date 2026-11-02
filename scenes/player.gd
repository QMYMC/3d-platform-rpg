extends CharacterBody3D

signal died

@export_range(1, 20, 1) var max_health: int = 2
@export var fall_death_height: float = -20.0
var health: int
var is_dead := false
var control_enabled := true
var damage_enabled := true
const heart_scene = preload("res://scenes/heart.tscn")

#移动参数
var direction: Vector2
var speed := 3.0
var acceleration:=8.0
var friction = 12.0
@onready var camera = $CameraController/Camera3D
@onready var skin = $Skin
@onready var move_state_machine = $AnimationTree.get("parameters/MoveStateMachine/playback")

# 跳跃参数
@export var jump_strength: float = 15.0
@export var double_jump_strength: float = 13.0
var air_jump_available := true
@export var jump_height: float = 2.25
@export var jump_time_to_peak: float = 0.4
@export var jump_time_to_descent: float = 0.3

@onready var jump_velocity: float = (2.0 * jump_height / jump_time_to_peak) * -1.0
@onready var jump_gravity: float = 2.0 * jump_height / (jump_time_to_peak * jump_time_to_peak)
@onready var fall_gravity: float = 2.0 * jump_height / (jump_time_to_descent * jump_time_to_descent)


func get_input() -> void:
	direction = Input.get_vector(
		"left", "right", "forward", "backward"
	).rotated(-camera.global_rotation.y)

	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			jump()
		elif air_jump_available and get_node("/root/RunSession").double_jump_unlocked:
			air_jump_available = false
			velocity.y = double_jump_strength
			$AirJumpSound.play()
			$AirJumpRing.show()
			$AirJumpRing.scale = Vector3.ONE
			create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).tween_property($AirJumpRing, "scale", Vector3(1.8, 1, 1.8), 0.25)
			$AirJumpFlash.start()

func _physics_process(delta: float) -> void:
	if is_dead or not control_enabled:
		return
	if global_position.y < fall_death_height:
		die()
		return
	if is_on_floor():
		air_jump_available = true
	get_input()

	velocity.x = direction.x * speed
	velocity.z = direction.y * speed

	apply_gravity(delta)
	move_and_slide()
	animate(delta)


func animate(delta: float) -> void:
	if not is_on_floor():
		move_state_machine.travel("Jump")
	elif direction:
		move_state_machine.travel("Running")
	else:
		move_state_machine.travel("Idle")
		
	if direction:
		skin.rotation.y = rotate_toward(
			skin.rotation.y,
			-direction.angle() + PI / 2.0,
			6.0 * delta
		)

func move(delta):
	var vel_2d = Vector2(velocity.x, velocity.z)
	if direction:
		vel_2d += direction * speed * delta * acceleration
		vel_2d = vel_2d.limit_length(speed)
		velocity.x = vel_2d.x
		velocity.z = vel_2d.y
	else:
		vel_2d = vel_2d.move_toward(Vector2.ZERO, speed * friction * delta)
		velocity.x = vel_2d.x
		velocity.y = vel_2d.y

func jump() -> void:
	velocity.y = jump_strength
	$JumpSound.play()

func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		var gravity = jump_gravity if velocity.y > 0 else fall_gravity
		velocity.y -= gravity * delta

func hit():
	if not is_dead and damage_enabled and $HitTimer.is_stopped():
		$AnimationTree.set("parameters/HitOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		$HitTimer.start()
		health -= 1
		set_hearts(health)
		$HitSound.play()
		if health <= 0:
			die()

func die() -> void:
	if is_dead or not damage_enabled:
		return
	is_dead = true
	health = 0
	set_hearts(health)
	direction = Vector2.ZERO
	velocity = Vector3.ZERO
	$HitTimer.stop()
	$AirJumpFlash.stop()
	$AirJumpRing.hide()
	$CameraController.set_process(false)
	$CameraController.set_physics_process(false)
	$CameraController.set_process_input(false)
	died.emit()

func _on_jump_detection_area_body_entered(enemy: Node3D) -> void:
	if not is_dead and control_enabled and velocity.y < 0 and enemy.alive:
		enemy.receive_stomp()
		air_jump_available = true
		jump(  )

func heal(amount: int) -> bool:
	if is_dead or not damage_enabled or health >= max_health or amount <= 0:
		return false
	health = mini(health + amount, max_health)
	set_hearts(health)
	return true

func finish_adventure() -> void:
	control_enabled = false
	damage_enabled = false
	direction = Vector2.ZERO
	velocity = Vector3.ZERO
	$AirJumpFlash.stop()
	$AirJumpRing.hide()
	$CameraController.set_process(false)
	$CameraController.set_physics_process(false)
	$CameraController.set_process_input(false)
	move_state_machine.travel("Idle")
		
func _ready() -> void:
	health = max_health
	set_hearts(health)


func set_hearts(value: int):
	for heart in $UI/HFlowContainer.get_children():
		$UI/HFlowContainer.remove_child(heart)
		heart.queue_free()
	for i in maxi(value, 0):
		var heart = heart_scene.instantiate()
		$UI/HFlowContainer.add_child(heart)
