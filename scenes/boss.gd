extends CharacterBody3D

signal status_changed
signal defeated
signal death_finished
signal stomp_blocked
signal attack_released(kind: int)
enum State { WAITING, WINDUP, ATTACK, VULNERABLE, RECOVER, DEAD, STOPPED }
const PROJECTILE = preload("res://scenes/magic_projectile.tscn")
const MELEE = &"2H_Melee_Attack_Slice"
const FAN = &"Spellcast_Shoot"
const DEATH = &"Death_A"
@export_range(1, 10, 1) var max_health := 3
@export_range(0.5, 5, 0.1) var charge_time := 1.5
@export_range(0.3, 5, 0.1) var cooldown := 1.2
@export_range(1, 10, 0.1) var vulnerable_duration := 5.0
@export_range(1, 10, 0.1) var projectile_speed := 3.0
@export var melee_radius := 3.6
var health: int
var alive := true
var combat_active := false
var state := State.WAITING
var attack_kind := 0
var locked_direction := Vector3.BACK
var released := false
var window_available := false
var death_animation_finished := false
@onready var player = get_tree().get_first_node_in_group("Player")
@onready var animator: AnimationPlayer = $Skin/AnimationPlayer

func _ready() -> void:
	health = max_health
	var library := AnimationLibrary.new()
	for name in [&"Idle", MELEE, FAN, &"Hit_A", DEATH]:
		var animation: Animation = animator.get_animation(name).duplicate(true)
		# Extracted source clips may contain old gameplay value/method tracks.
		# Only keep imported movement; all gameplay events below are local.
		for track in range(animation.get_track_count() - 1, -1, -1):
			if animation.track_get_type(track) in [Animation.TYPE_METHOD, Animation.TYPE_VALUE]:
				animation.remove_track(track)
		animation.loop_mode = Animation.LOOP_LINEAR if name == &"Idle" else Animation.LOOP_NONE
		if name in [MELEE, FAN]:
			var track := animation.add_track(Animation.TYPE_METHOD)
			animation.track_set_path(track, NodePath(".."))
			animation.track_insert_key(track, 0.45 if name == MELEE else 0.3, {"method": &"_release_attack", "args": []})
		library.add_animation(name, animation)
	for name in animator.get_animation_library_list():
		animator.remove_animation_library(name)
	animator.add_animation_library(&"", library)
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	animator.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	animator.animation_finished.connect(_on_animation_finished)
	$StateTimer.timeout.connect(_on_state_timeout)
	$VolleyTimer.timeout.connect(_open_window)
	$ShieldFlash.timeout.connect(_end_shield_flash)
	animator.play(&"Idle")
	_update_visuals()

func start_battle() -> void:
	if state != State.WAITING or not alive:
		return
	combat_active = true
	_begin_windup()

func _physics_process(_delta: float) -> void:
	if state == State.WINDUP:
		$ChargeOrb.scale = Vector3.ONE * (0.4 + 0.8 * (1.0 - $WindupTimer.time_left / maxf(charge_time, 0.1)))

func _begin_windup() -> void:
	if not alive or not combat_active or not is_instance_valid(player) or player.is_dead:
		return
	state = State.WINDUP
	released = false
	window_available = false
	var target: Vector3 = player.global_position + Vector3.UP
	var facing := target - global_position
	rotation.y = atan2(facing.x, facing.z)
	locked_direction = (target - $Muzzle.global_position).normalized()
	$WindupTimer.start(charge_time)
	animator.speed_scale = (0.45 if attack_kind == 0 else 0.3) / charge_time
	animator.play(MELEE if attack_kind == 0 else FAN, 0.1)
	_update_visuals()

func _release_attack() -> void:
	if not alive or not combat_active or state != State.WINDUP or released or player.is_dead:
		return
	released = true
	state = State.ATTACK
	$WindupTimer.stop()
	animator.speed_scale = 1.0
	if attack_kind == 0:
		var offset: Vector3 = player.global_position - global_position
		var horizontal := Vector3(offset.x, 0, offset.z)
		var facing := Vector3(locked_direction.x, 0, locked_direction.z).normalized()
		if horizontal.length() <= melee_radius and horizontal.normalized().dot(facing) >= cos(deg_to_rad(65)) and offset.y < 1.1:
			var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.1, player.global_position + Vector3.UP, 1, [get_rid()])
			if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				player.hit()
	else:
		for angle in [-22.0, 0.0, 22.0]:
			var shot = PROJECTILE.instantiate()
			get_tree().current_scene.add_child(shot)
			var origin: Vector3 = $Muzzle.global_position
			shot.launch(origin, origin + locked_direction.rotated(Vector3.UP, deg_to_rad(angle)) * 10, self, projectile_speed)
		$VolleyTimer.start(2.2)
	$AttackSound.play()
	_update_visuals()
	attack_released.emit(attack_kind)

func _on_animation_finished(name: StringName) -> void:
	if name == DEATH and not alive:
		death_animation_finished = true
		death_finished.emit()
	elif state == State.ATTACK and name == MELEE:
		_open_window()
	elif state == State.ATTACK and name == FAN:
		animator.play(&"Idle", 0.1)
	elif state == State.RECOVER and name == &"Hit_A":
		animator.play(&"Idle", 0.1)

func _open_window() -> void:
	if not alive or not combat_active or state != State.ATTACK:
		return
	clear_projectiles()
	state = State.VULNERABLE
	window_available = true
	$StateTimer.start(vulnerable_duration)
	animator.play(&"Idle", 0.15)
	_update_visuals()

func receive_stomp() -> void:
	if not alive:
		return
	if state != State.VULNERABLE or not window_available:
		$Shield.show()
		$ShieldFlash.start()
		$Label.text = "护盾有效！等绿光再踩"
		$Label.show()
		stomp_blocked.emit()
		return
	window_available = false
	health -= 1
	$HitSound.play()
	if health == 0:
		defeat()
	else:
		_enter_recover(true)
	status_changed.emit()

func _enter_recover(was_hit := false) -> void:
	state = State.RECOVER
	window_available = false
	attack_kind = 1 - attack_kind
	$StateTimer.start(cooldown)
	animator.speed_scale = 1.0
	animator.play(&"Hit_A" if was_hit else &"Idle", 0.1)
	_update_visuals()

func _on_state_timeout() -> void:
	if not alive or not combat_active:
		return
	if state == State.VULNERABLE:
		_enter_recover()
	elif state == State.RECOVER:
		_begin_windup()

func _end_shield_flash() -> void:
	_update_visuals()

func status_text() -> String:
	match state:
		State.WAITING: return "穿过入口开战 · 红色躲，绿色踩"
		State.WINDUP: return "红色预兆：离开扇形范围或跳起" if attack_kind == 0 else "红色预兆：三发扇形弹，横移躲避"
		State.ATTACK: return "攻击中 · 护盾有效"
		State.VULNERABLE: return "绿色虚弱：现在跳起踩头！"
		State.RECOVER: return "护盾恢复 · 准备下一轮"
		State.DEAD: return "守门者已倒下"
	return "战斗已停止"

func _update_visuals() -> void:
	$Shield.visible = alive and state != State.VULNERABLE
	$WeakRing.visible = state == State.VULNERABLE
	$MeleeWarning.visible = state == State.WINDUP and attack_kind == 0
	$FanWarning.visible = state == State.WINDUP and attack_kind == 1
	$ChargeOrb.visible = state == State.WINDUP
	$Label.text = status_text()
	$Label.hide()
	status_changed.emit()

func clear_projectiles() -> void:
	for shot in get_tree().get_nodes_in_group("EnemyProjectiles"):
		if shot.caster_id == get_instance_id():
			shot.cancel()

func _stop_actions() -> void:
	combat_active = false
	window_available = false
	for timer in [$StateTimer, $WindupTimer, $VolleyTimer, $ShieldFlash]:
		timer.stop()
	animator.speed_scale = 1.0
	$AttackSound.stop()

func stop_combat() -> void:
	_stop_actions()
	clear_projectiles()
	if alive:
		state = State.STOPPED
		animator.play(&"Idle")
	_update_visuals()

func defeat() -> void:
	if not alive or health > 0:
		return
	alive = false
	state = State.DEAD
	_stop_actions()
	$CollisionShape3D.set_deferred("disabled", true)
	animator.play(DEATH, 0.1)
	_update_visuals()
	# Existing flying shots are cleared by the main outcome resolver, after
	# all contacts in this physics frame have had a chance to kill the player.
	defeated.emit()
