extends "res://tests/progression_test.gd"

const MAGE = preload("res://scenes/mage.tscn")
const BOLT = preload("res://scenes/magic_projectile.tscn")
var fired: Array[Dictionary] = []
var hit_capture := {}
var stomps: Array[Dictionary] = []
var recording := false
var clip_times: Array[int] = []
var last_capture := 0
var clip_images: Array[Image] = []

func capture_clip_frame() -> void:
	var now := Time.get_ticks_msec()
	if not recording or now - last_capture < 100:
		return
	last_capture = now
	var frame := root.get_texture().get_image()
	frame.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	clip_images.append(frame)
	clip_times.append(now)

func start_clip() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/mage_clip_frames"))
	clip_times.clear()
	clip_images.clear()
	last_capture = 0
	recording = true

func finish_clip() -> void:
	if not recording:
		return
	recording = false
	for i in clip_images.size():
		clip_images[i].save_png("res://.godot/mage_clip_frames/frame_%03d.png" % i)
	clip_images.clear()
	var output := FileAccess.open("res://test_output/mages/clip_frames.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"times_ms": clip_times, "frame_count": clip_times.size()}))
	check(clip_times.size() > 30, "short gameplay recording captured from rendered frames")

func record_stomp(body: Node3D) -> void:
	if body.is_in_group("Mages") and not body.alive:
		stomps.append({"name": body.name, "air": player.air_jump_available, "velocity": player.velocity.y})
		call_deferred("capture_stomp")

func capture_stomp() -> void:
	await screenshot("04_mage_stomp")

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await frames(2)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://test_output/mages/" + name + ".png") == OK, "screenshot: " + name)

func load_fixture() -> Node3D:
	check(change_scene_to_file("res://scenes/test_level.tscn") == OK, "isolated collision fixture loads")
	await scene_changed
	player = current_scene.get_node("Characters/Player")
	session = root.get_node("RunSession")
	await frames(20)
	var mage = MAGE.instantiate()
	mage.name = "FixtureMage"
	mage.notice_radius = 0.0
	mage.position = player.position + Vector3(4, 0, 0)
	current_scene.add_child(mage)
	return mage

func bolt(caster: CharacterBody3D, origin: Vector3, target: Vector3, speed := 600.0) -> Node3D:
	var shot = BOLT.instantiate()
	current_scene.add_child(shot)
	shot.launch(origin, target, caster, speed)
	return shot

func wall(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	current_scene.add_child(body)
	body.position = pos
	return body

func record_shot(shot: Node3D) -> void:
	fired.append({"reference": weakref(shot), "direction": shot.direction, "origin": shot.global_position})

func wait_for_shot(mage: Node3D) -> void:
	for i in 200:
		if not fired.is_empty():
			return
		await frames(1)
	check(false, "animation release event did not fire")

func collision_suite() -> void:
	var mage = await load_fixture()
	var chest: Vector3 = player.global_position + Vector3.UP
	var thin := wall(chest + Vector3.RIGHT * 1.5, Vector3(0.02, 3, 3))
	await frames(2)
	mage.notice_radius = 7.0
	check(not mage.can_detect_player(), "actual thin wall blocks mage line of sight")
	await frames(90)
	check(mage.state == mage.State.IDLE and get_nodes_in_group("EnemyProjectiles").is_empty(), "occluded player never starts a cast")
	mage.notice_radius = 0
	var near_wall := wall(mage.position + Vector3(-0.55, 1.15, 0), Vector3(0.02, 3, 3))
	mage.rotation.y = -PI / 2
	await frames(2)
	mage.notice_radius = 7
	check(not mage.can_detect_player(), "body-eye line of sight cannot see through wall behind protruding muzzle")
	mage.notice_radius = 0
	near_wall.queue_free()
	await frames(2)
	var shot = bolt(mage, chest + Vector3.RIGHT * 4, chest)
	hit_capture = {}
	shot.tree_exiting.connect(func(): hit_capture["position"] = shot.global_position)
	await frames(3)
	check(not is_instance_valid(shot) and player.health == player.max_health, "600 m/s projectile cannot tunnel through 2 cm wall")
	check(hit_capture.has("position") and hit_capture.position.x > thin.position.x, "sweep stops at first wall contact rather than end position")
	thin.queue_free()
	await frames(2)
	var ignored_area := Area3D.new()
	ignored_area.collision_layer = 2
	ignored_area.collision_mask = 2
	var area_shape := CollisionShape3D.new()
	var area_sphere := SphereShape3D.new()
	area_sphere.radius = 0.3
	area_shape.shape = area_sphere
	ignored_area.add_child(area_shape)
	current_scene.add_child(ignored_area)
	ignored_area.position = chest + Vector3.RIGHT * 2
	await frames(2)
	shot = bolt(mage, chest + Vector3.RIGHT * 4, chest)
	await frames(3)
	check(player.health == player.max_health - 1 and not is_instance_valid(shot), "swept projectile hits real player once")
	check(session.collected_rune_ids.is_empty() and session.checkpoint_id == &"", "projectile crossing trigger areas does not activate collectibles or checkpoints")
	await frames(5)
	check(player.health == player.max_health - 1, "one projectile cannot repeat damage")
	shot = bolt(mage, chest, chest + Vector3.LEFT)
	await frames(2)
	check(not is_instance_valid(shot) and player.health == player.max_health - 1, "start overlap is detected and hit protection rejects immediate second damage")
	await frames(45)
	var orphan = bolt(mage, chest + Vector3.UP * 8, chest + Vector3.UP * 8 + Vector3.RIGHT, 0)
	orphan.caster_id = 0
	shot = bolt(mage, chest + Vector3.RIGHT * 0.7, chest + Vector3.LEFT)
	await frames(3)
	check(player.is_dead and current_scene.failed, "near-distance swept hit uses existing lethal failure flow")
	check(get_nodes_in_group("EnemyProjectiles").is_empty(), "failure cleans every projectile, including one without a live caster")
	check(not mage.combat_active and mage.get_node("ChargeTimer").is_stopped() and mage.get_node("CooldownTimer").is_stopped(), "failure stops mage and both timers")
	mage = await load_fixture()
	fired.clear()
	mage.projectile_fired.connect(record_shot)
	mage.notice_radius = 7
	for i in 20:
		await frames(1)
		if mage.state == mage.State.CHARGE:
			break
	check(mage.state == mage.State.CHARGE, "unobstructed player starts charge")
	var locked: Vector3 = mage.locked_target
	steer(Vector2(0, 1))
	await frames(25)
	steer(Vector2.ZERO)
	check(mage.locked_target == locked, "moving player does not change locked target")
	await wait_for_shot(mage)
	check(fired.size() == 1, "one animation release produces exactly one shot")
	var expected: Vector3 = (locked - fired[0].origin).normalized()
	check(fired[0].direction.is_equal_approx(expected), "release direction points at original lock position")
	await frames(15)
	var live_shot = fired[0].reference.get_ref()
	check(is_instance_valid(live_shot) and live_shot.direction.is_equal_approx(expected), "flying projectile never homes toward player")
	await frames(60)
	check(player.health == player.max_health, "actual lateral input evades locked straight projectile")
	check(fired.size() == 1, "recovery and cooldown do not replay cast animation")
	mage._release_projectile()
	check(fired.size() == 1, "repeated release callback cannot duplicate projectile")
	check(not get_nodes_in_group("EnemyProjectiles").is_empty(), "projectile is still in flight before caster defeat")
	mage.defeat()
	await frames(2)
	check(get_nodes_in_group("EnemyProjectiles").is_empty(), "caster defeat clears its own remaining projectile")
	check(not mage.alive and mage.get_node("CollisionShape3D").disabled, "mage death removes blocking collision")
	check(mage.get_node("ChargeTimer").is_stopped() and mage.get_node("CooldownTimer").is_stopped(), "mage death stops timers")
	mage._release_projectile()
	await frames(150)
	check(fired.size() == 1 and get_nodes_in_group("EnemyProjectiles").is_empty(), "dead mage cannot emit delayed attacks")
	var source_animation = load("res://graphics/characters/skeleton mage/Skeleton_Mage.glb").instantiate()
	check(source_animation.get_node("AnimationPlayer").get_animation("Idle").loop_mode == Animation.LOOP_NONE, "shared imported animation remains unchanged")
	check(mage.animator.get_animation("Idle").loop_mode == Animation.LOOP_LINEAR and mage.animator.get_animation("Spellcast_Shoot").loop_mode == Animation.LOOP_NONE, "local idle loops while cast remains a single clip")
	source_animation.free()
	var expired = bolt(mage, player.position + Vector3.UP * 10, player.position + Vector3.UP * 10 + Vector3.RIGHT, 0)
	expired.lifetime = 0.05
	await frames(8)
	check(not is_instance_valid(expired), "projectile expires at configured lifetime")

func gate_collision_suite() -> void:
	check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "main scene loads for gate sweep")
	await scene_changed
	player = current_scene.get_node("Characters/Player")
	session = root.get_node("RunSession")
	await frames(20)
	var mage = current_scene.get_node("RangedGuards/RuinsMage")
	var shot = bolt(mage, Vector3(17, 3, -50), Vector3(17, 3, -60), 600)
	hit_capture = {}
	shot.tree_exiting.connect(func(): hit_capture["position"] = shot.global_position)
	await frames(3)
	check(not is_instance_valid(shot) and hit_capture.position.z > -54, "closed rune gate blocks a full-step high-speed projectile")
	shot = bolt(mage, mage.global_position + Vector3.UP, mage.global_position + Vector3.UP + Vector3.BACK, 1)
	await frames(2)
	check(is_instance_valid(shot), "projectile ignores caster body and enemy collision layer")
	shot.cancel()

func real_combat() -> void:
	player.get_node("JumpDetectionArea").body_entered.connect(record_stomp)
	await camp_to_ruins()
	await collect_ruins()
	await go(Vector2(0, -22.2))
	await go(Vector2(0, -24.8), true)
	await go(Vector2(0, -28.5))
	var mage = current_scene.get_node("RangedGuards/RuinsMage")
	player.get_node("CameraController").rotation.y = -PI / 2 + 0.12
	fired.clear()
	mage.projectile_fired.connect(record_shot)
	await go(Vector2(1, -28.5))
	check(mage.state == mage.State.CHARGE, "actual approach triggers visible mage charge")
	await screenshot("01_mage_charge")
	await wait_for_shot(mage)
	for i in 150:
		await frames(1)
		if player.health < player.max_health:
			break
	check(player.health == player.max_health - 1 and not player.is_dead, "standing in actual mage projectile path takes one protected hit")
	await screenshot("03_player_hit")
	# Recover using the existing bottle, then return for the dodge/stomp trial.
	await go(Vector2(0, -24.8))
	await go(Vector2(0, -20))
	await go(Vector2(2, -19))
	check(player.health == player.max_health, "existing healing pickup restores health after mage hit")
	await go(Vector2(0, -22.2))
	await go(Vector2(0, -24.8), true)
	await go(Vector2(0, -28.5))
	fired.clear()
	start_clip()
	await go(Vector2(1, -28.5))
	await go(Vector2(1, -27))
	await wait_for_shot(mage)
	await frames(12)
	await screenshot("02_projectile_flight")
	await frames(90)
	check(player.health == player.max_health, "input-driven sidestep dodges ruins mage shot")
	await defeat_guard("RuinsMage")
	finish_clip()
	check(not stomps.is_empty() and stomps[0].air and stomps[0].velocity > 0, "real mage stomp restores air jump at the instant of rebound")
	await screenshot("04_mage_defeated")
	await go(Vector2(17, -29))
	check(session.double_jump_unlocked and session.collected_rune_ids.size() == 2, "combat route retains collected runes and unlocks ability")
	await to_high_platform()
	check(not current_scene.get_node("RangedGuards/CourtyardMage").alive, "advanced guard is defeated through actual jumping and stomp")
	check(stomps.any(func(event: Dictionary): return event.name == &"CourtyardMage" and event.air and event.velocity > 0), "advanced mage stomp also restores air jump during rebound")
	await collect_courtyard()
	progress([&"camp", &"ruins", &"courtyard"], true, &"courtyard")

func retry_lifecycle() -> void:
	# Reload normally to restore both guards; then fail during alternating
	# charge / projectile flight. Each retry must keep all run progress.
	await walk_to_death(Vector2.RIGHT)
	await retry(&"courtyard")
	for cycle in 3:
		var mage = current_scene.get_node("RangedGuards/CourtyardMage")
		fired.clear()
		mage.projectile_fired.connect(record_shot)
		await go(Vector2(17, -34.6))
		await go(Vector2(17, -37.1), true)
		for i in 90:
			if mage.state == mage.State.CHARGE:
				break
			await frames(1)
		if cycle == 1:
			await wait_for_shot(mage)
			check(not get_nodes_in_group("EnemyProjectiles").is_empty(), "failure scenario has live projectile in flight")
		else:
			check(mage.state == mage.State.CHARGE, "failure scenario is in charge wind-up")
		player.die()
		await frames(3)
		check(get_nodes_in_group("EnemyProjectiles").is_empty(), "failure immediately clears hostile projectiles")
		for guard in get_nodes_in_group("Mages"):
			check(not guard.combat_active and guard.get_node("ChargeTimer").is_stopped() and guard.get_node("CooldownTimer").is_stopped(), "failure stops each mage without pending timer")
		await frames(100)
		check(get_nodes_in_group("EnemyProjectiles").is_empty(), "waiting after death cannot create delayed projectile")
		await retry(&"courtyard")
		progress([&"camp", &"ruins", &"courtyard"], true, &"courtyard")
		for guard in get_nodes_in_group("Mages"):
			check(guard.alive and guard.combat_active and not guard.get_node("CollisionShape3D").disabled and guard.state == guard.State.IDLE, "retry restores living guard safely outside spawn detection")
		check(get_nodes_in_group("EnemyProjectiles").is_empty(), "retry scene contains no old projectile")
		print("MAGE_RETRY ", cycle + 1)

func run() -> void:
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(capture_clip_frame)
	if "--combat-only" in OS.get_cmdline_user_args():
		check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "main scene loads for visual combat check")
		await scene_changed
		player = current_scene.get_node("Characters/Player")
		session = root.get_node("RunSession")
		await frames(20)
		await real_combat()
		print("MAGE_VISUAL_RESULT checks=", checks, " failures=", failures)
		quit(0 if failures == 0 else 1)
		return
	await collision_suite()
	await gate_collision_suite()
	check(get_nodes_in_group("Mages").size() == 2, "exactly two guards placed in main level")
	for guard in get_nodes_in_group("Mages"):
		check(not guard.can_detect_player(), "camp spawn is outside guard detection")
	await real_combat()
	await retry_lifecycle()
	print("MAGE_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
