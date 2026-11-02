extends CharacterBody3D

@onready var move_state_machine = $AnimationTree.get("parameters/MoveStateMachine/playback")
@onready var player = get_tree().get_first_node_in_group("Player")
@export var notice_radius = 20.0
@export var attack_radius = 2.0
@export var speed := 2.0
@export var chase_limit: float = 0.0
@onready var home_position: Vector3 = position
@export var can_damage: bool = false:
	set(value):
		can_damage = value and alive and combat_active
		if can_damage and $SwordSound.playing == false:
			$SwordSound.play()
@export var has_hit_this_attack := false
@export var alive := true
var combat_active := true

func _physics_process(delta: float) -> void:
	if alive and combat_active and chase_limit > 0.0 and home_position.distance_to(player.position) > chase_limit:
		velocity = Vector3.ZERO
		move_state_machine.travel("Idle")
		return
	if alive and combat_active and not player.is_dead and position.distance_to(player.position) < notice_radius:
		var target_dir = (player.position - position).normalized()
		var target_vec2 = Vector2(target_dir.x, target_dir.z)
		rotation.y = rotate_toward(rotation.y, -target_vec2.angle() + PI/2, delta * 6.0)
		if position.distance_to(player.position) > attack_radius:
			velocity = Vector3(target_vec2.x, 0, target_vec2.y) * speed
			move_state_machine.travel("Walking")
		else:
			velocity = Vector3.ZERO
			move_state_machine.travel("Idle")
		
		if not is_on_floor():
			velocity.y -=2
		else:
			velocity.y = 0
		
		move_and_slide()

		if can_damage and not has_hit_this_attack and position.distance_to(player.position) < attack_radius:
			has_hit_this_attack = true
			player.hit()

func _on_attack_timer_timeout() -> void:
	if not alive or not combat_active or player.is_dead:
		return
	$AttackTimer.wait_time = randf_range(3,4)
	if position.distance_to(player.position) < attack_radius:
		has_hit_this_attack = false
		$AnimationTree.set("parameters/AttackOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	
func defeat():
	if not alive:
		return
	alive = false
	stop_combat()
	$CollisionShape3D.set_deferred("disabled", true)
	var tween = create_tween()
	tween.tween_method(death_animation, 0.0, 1.0, 0.5)

func receive_stomp() -> void:
	defeat()
	
func death_animation(value: float):
	$AnimationTree.set("parameters/DeathBlend/blend_amount", value)
	
func stop_combat() -> void:
	combat_active = false
	can_damage = false
	has_hit_this_attack = true
	velocity = Vector3.ZERO
	$AttackTimer.stop()
	$SwordSound.stop()
	$AnimationTree.set("parameters/AttackOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
