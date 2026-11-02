extends CharacterBody3D

signal charge_started(target: Vector3)
signal projectile_fired(projectile: Node3D)

enum State { IDLE, CHARGE, SHOOT, COOLDOWN, STOPPED, DEAD }
const RELEASE_TIME := 0.3
const PROJECTILE = preload("res://scenes/magic_projectile.tscn")
@export var notice_radius: float = 7.0
@export var charge_time: float = 1.2
@export var cooldown: float = 2.8
@export var projectile_speed: float = 4.5
var alive := true
var combat_active := true
var state := State.IDLE
var locked_target := Vector3.ZERO
var emitted := false
@onready var player = get_tree().get_first_node_in_group("Player")
@onready var animator: AnimationPlayer = $Skin/AnimationPlayer

func _ready() -> void:
	# Imported animations are shared. Keep loop/event edits local to this mage.
	var library := AnimationLibrary.new()
	for name in [&"Idle", &"Spellcast_Shoot", &"Death_C_Skeletons"]:
		var animation: Animation = animator.get_animation(name).duplicate(true)
		animation.loop_mode = Animation.LOOP_LINEAR if name == &"Idle" else Animation.LOOP_NONE
		if name == &"Spellcast_Shoot":
			var track := animation.add_track(Animation.TYPE_METHOD)
			animation.track_set_path(track, NodePath(".."))
			animation.track_insert_key(track, RELEASE_TIME, {"method": &"_release_projectile", "args": []})
		library.add_animation(name, animation)
	for name in animator.get_animation_library_list():
		animator.remove_animation_library(name)
	animator.add_animation_library(&"", library)
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	animator.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	animator.animation_finished.connect(_on_animation_finished)
	$CooldownTimer.timeout.connect(_on_cooldown_timeout)
	animator.play(&"Idle")

func can_detect_player() -> bool:
	if not alive or not combat_active or not is_instance_valid(player) or player.is_dead:
		return false
	if global_position.distance_to(player.global_position) > notice_radius:
		return false
	var eye := global_position + Vector3.UP * 1.15
	var ray := PhysicsRayQueryParameters3D.create(eye, player.global_position + Vector3.UP, 3, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.collider == player

func _physics_process(_delta: float) -> void:
	if not alive or not combat_active:
		return
	if state == State.IDLE and can_detect_player():
		_begin_charge()
	elif state == State.CHARGE:
		var progress := clampf(1.0 - $ChargeTimer.time_left / maxf(charge_time, 0.1), 0, 1)
		$Muzzle/ChargeOrb.scale = Vector3.ONE * lerpf(0.35, 1.3, progress)

func _begin_charge() -> void:
	state = State.CHARGE
	emitted = false
	locked_target = player.global_position + Vector3.UP
	var facing := locked_target - global_position
	rotation.y = atan2(facing.x, facing.z)
	$Muzzle/ChargeOrb.show()
	$ChargeRing.show()
	$Label.text = "蓄力 · 目标已锁定"
	$ChargeTimer.start(maxf(charge_time, 0.1))
	# Stretch only the wind-up. The event at the outstretched-hand pose
	# fires after charge_time; recovery then plays at the original speed.
	animator.speed_scale = RELEASE_TIME / maxf(charge_time, 0.1)
	animator.play(&"Spellcast_Shoot", 0.1)
	charge_started.emit(locked_target)

func _release_projectile() -> void:
	if not alive or not combat_active or state != State.CHARGE or emitted:
		return
	if not is_instance_valid(player) or player.is_dead:
		stop_combat()
		return
	emitted = true
	state = State.SHOOT
	$ChargeTimer.stop()
	$Muzzle/ChargeOrb.hide()
	$ChargeRing.hide()
	$Label.text = "发射"
	animator.speed_scale = 1.0
	var projectile = PROJECTILE.instantiate()
	get_tree().current_scene.add_child(projectile)
	var origin: Vector3 = $Muzzle.global_position
	# A wall may enter the short hand-to-body segment during wind-up.
	# Spawn at its surface so the projectile's initial overlap stops it.
	var muzzle_ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.15, origin, 1, [get_rid()])
	var obstruction := get_world_3d().direct_space_state.intersect_ray(muzzle_ray)
	if not obstruction.is_empty():
		origin = obstruction.position
	projectile.launch(origin, locked_target, self, projectile_speed)
	$CastSound.play()
	projectile_fired.emit(projectile)

func _on_animation_finished(animation: StringName) -> void:
	if animation == &"Spellcast_Shoot" and alive and combat_active and state == State.SHOOT:
		state = State.COOLDOWN
		$Label.text = "冷却 · 可接近踩头"
		animator.play(&"Idle", 0.15)
		$CooldownTimer.start(maxf(cooldown, 0.1))

func _on_cooldown_timeout() -> void:
	if alive and combat_active:
		state = State.IDLE
		$Label.text = "守卫法师 · 踩头击败"

func clear_projectiles() -> void:
	for projectile in get_tree().get_nodes_in_group("EnemyProjectiles"):
		if projectile.caster_id == get_instance_id():
			projectile.cancel()

func stop_combat() -> void:
	combat_active = false
	state = State.STOPPED if alive else State.DEAD
	$ChargeTimer.stop()
	$CooldownTimer.stop()
	$Muzzle/ChargeOrb.hide()
	$ChargeRing.hide()
	$CastSound.stop()
	clear_projectiles()
	animator.speed_scale = 1.0
	if alive:
		animator.play(&"Idle")
		$Label.text = "战斗已停止"

func defeat() -> void:
	if not alive:
		return
	alive = false
	stop_combat()
	$CollisionShape3D.set_deferred("disabled", true)
	$Label.text = "已击败"
	animator.play(&"Death_C_Skeletons", 0.1)

func receive_stomp() -> void:
	defeat()
