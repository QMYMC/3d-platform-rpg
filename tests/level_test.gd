extends SceneTree

# Traversal uses the player's real Input actions and physics. No player
# transform/velocity writes or direct jump/checkpoint calls are used.
var failures := 0
var checks := 0
var player
var session: Node
const BUTTONS = "FailureUI/FailureScreen/CenterContainer/PanelContainer/MarginContainer/Buttons/"
const OUTPUT = "res://test_output/level/"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/player"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/level"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/progression"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/mages"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/boss"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/environment"))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for i in count:
		await physics_frame
	# Several physics ticks can occur within one rendered frame (especially
	# while recording). Count ticks, then resume outside the physics callback.
	await process_frame

func steer(direction: Vector2) -> void:
	var local := direction.rotated(player.get_node("CameraController").global_rotation.y)
	for action in ["left", "right", "forward", "backward"]:
		Input.action_release(action)
	if local.x < -0.01:
		Input.action_press("left", -local.x)
	elif local.x > 0.01:
		Input.action_press("right", local.x)
	if local.y < -0.01:
		Input.action_press("forward", -local.y)
	elif local.y > 0.01:
		Input.action_press("backward", local.y)

func go(target: Vector2, jump := false, air_jump := false) -> void:
	if player.is_dead:
		check(false, "cannot traverse after unexpected death")
		quit(1)
		return
	print("WALK ", Vector2(player.position.x, player.position.z), " -> ", target, " jump=", jump)
	if jump:
		check(player.is_on_floor(), "single jump starts grounded")
		Input.action_press("jump")
	for frame in 480:
		var offset := target - Vector2(player.position.x, player.position.z)
		if offset.length() < 0.09 and player.is_on_floor():
			steer(Vector2.ZERO)
			Input.action_release("jump")
			await frames(2)
			check(not player.is_dead, "reached " + str(target) + " through movement")
			return
		steer(offset.normalized() * clampf(offset.length() * 3.0, 0.6, 1.0) if offset.length() > 0.07 else Vector2.ZERO)
		if frame == 28 and air_jump:
			Input.action_press("jump")
		await frames(1)
		Input.action_release("jump")
		if player.is_dead:
			break
	steer(Vector2.ZERO)
	check(false, "route blocked or player died at " + str(player.position) + " target=" + str(target))
	quit(1)
	await process_frame

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await frames(3)
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUTPUT + name + ".png")
	check(error == OK, "screenshot saved: " + name)

func camera_check() -> void:
	var arm = player.get_node("CameraController")
	var original: Vector3 = arm.rotation
	for yaw in [0.0, PI / 2, -PI / 2, PI]:
		arm.rotation.y = yaw
		await frames(3)
		var query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.08
		query.shape = sphere
		query.transform = player.get_node("CameraController/Camera3D").global_transform
		query.collision_mask = 1
		check(player.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "camera outside terrain at yaw " + str(yaw))
	arm.rotation = original
	await frames(3)

func defeat_guard(guard_name: String) -> void:
	var mage = current_scene.get_node_or_null("RangedGuards/" + guard_name)
	if mage == null or not mage.alive:
		return
	var return_point := Vector2(player.position.x, player.position.z)
	var target := Vector2(mage.position.x, mage.position.z)
	if guard_name == "RuinsMage":
		# Observe from the side of the corridor, dodge the position-locked
		# shot, then approach during recovery. No old route checks are skipped.
		var side := -1.0 if player.position.x < mage.position.x else 1.0
		var observe_x: float = maxf(player.position.x, target.x - 5.5) if side < 0 else player.position.x
		await go(Vector2(observe_x, target.y + 1.35))
		for i in 150:
			if mage.state == mage.State.SHOOT or mage.state == mage.State.COOLDOWN:
				break
			await frames(1)
		await go(Vector2(target.x + side * 2.0, target.y + 1.2))
	await go(target, true, guard_name == "CourtyardMage")
	check(not mage.alive and mage.get_node("CollisionShape3D").disabled, "real stomp defeats " + guard_name)
	await go(return_point)

func walk_to_death(direction: Vector2) -> void:
	steer(direction.normalized())
	for i in 600:
		await frames(1)
		if player.is_dead:
			break
	steer(Vector2.ZERO)
	check(player.is_dead and current_scene.failed, "walking off terrain enters existing failure flow")
	check(current_scene.get_node("FailureUI/FailureScreen").visible, "failure UI visible")
	check(current_scene.get_node("Characters/Enemy/AttackTimer").is_stopped(), "enemy timer stopped on failure")

func retry(expected: StringName) -> void:
	current_scene.get_node(BUTTONS + "RetryButton").pressed.emit()
	await scene_changed
	player = current_scene.get_node("Characters/Player")
	var expected_position := Vector3(0, 0.08, 3)
	if expected != &"":
		for checkpoint in get_nodes_in_group("Checkpoints"):
			if checkpoint.checkpoint_id == expected:
				expected_position = checkpoint.get_node("Spawn").global_position
	check(player.position.is_equal_approx(expected_position), "retry spawn matches " + str(expected))
	check(player.health == player.max_health and player.get_node("UI/HFlowContainer").get_child_count() == player.max_health, "full health and hearts restored")
	check(player.get_node("HitTimer").is_stopped() and player.velocity == Vector3.ZERO, "hit timer and velocity reset")
	var enemy = current_scene.get_node("Characters/Enemy")
	check(enemy.alive and enemy.combat_active and not enemy.can_damage and not enemy.get_node("CollisionShape3D").disabled, "enemy reset alive with collision and no active damage")
	check(enemy.position.is_equal_approx(Vector3(4.5, 0.08, -3)), "enemy authored position restored")
	check(enemy.get_node("AttackTimer").wait_time == 5.0 and not enemy.get_node("AttackTimer").is_stopped(), "attack timer initial state restored")
	check(player.get_node("CameraController").is_processing_input() and is_zero_approx(player.get_node("CameraController").rotation.y), "camera control and orientation restored")
	check(not current_scene.failed and not current_scene.get_node("FailureUI/FailureScreen").visible, "failure state reset")
	check(session.checkpoint_id == expected, "session retains only expected checkpoint ID")
	await frames(10)

func audit_collision() -> void:
	var library = load("res://mesh/level_meshes.tres")
	for item in library.get_item_list():
		check(library.get_item_shapes(item).size() >= 2, "MeshLibrary collision present: " + library.get_item_name(item))
	var checked := 0
	var bad := 0
	var overlays: Array[RID] = []
	for obstacle in get_nodes_in_group("SolidDecor"):
		# Separately tested obstacles must not hide the underlying floor.
		overlays.append(obstacle.get_rid())
	if current_scene.has_node("BossArena/JumpPlatform"):
		# Probe the GridMap floor underneath the new optional raised stone.
		overlays.append(current_scene.get_node("BossArena/JumpPlatform").get_rid())
	for node in current_scene.get_node("Level").get_children():
		if not node is GridMap or node.name == "LavaSurface":
			continue
		for cell in node.get_used_cells():
			var center: Vector3 = node.to_global(node.map_to_local(cell))
			var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 2, center - Vector3.UP, 1, overlays)
			var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
			checked += 1
			if hit.is_empty() or absf(hit.position.y - (center.y + 0.5)) > 0.02:
				bad += 1
	check(bad == 0, "all " + str(checked) + " walkable GridMap cells have live physics collision")

func camp_to_ruins() -> void:
	await go(Vector2(0, -9.6))
	await go(Vector2(0, -12.1), true)
	await go(Vector2(0, -16))
	await screenshot("checkpoint_inactive")
	await go(Vector2(0, -20))
	check(session.checkpoint_id == &"ruins", "ruins checkpoint activated by walking")

func return_to_courtyard() -> void:
	for pair in [[-51.4, -48.9], [-46.4, -43.9], [-41.4, -38.9], [-36.4, -33.9]]:
		await go(Vector2(17, pair[0]))
		await go(Vector2(17, pair[1]), true)
		if pair[1] == -43.9:
			await defeat_guard("CourtyardMage")
	await go(Vector2(17, -29))

func run() -> void:
	check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "configured main scene loads")
	await scene_changed
	player = current_scene.get_node("Characters/Player")
	session = root.get_node("RunSession")
	check(session.checkpoint_id == &"", "new run has no saved checkpoint")
	await frames(20)
	audit_collision()
	current_scene.get_node("Level/Checkpoint_ruins")._on_body_entered(current_scene.get_node("Characters/Enemy"))
	check(session.checkpoint_id == &"", "enemy cannot activate checkpoint")
	current_scene.get_node("Level/LavaHazard")._on_body_entered(current_scene.get_node("Characters/Enemy"))
	check(not player.is_dead and current_scene.get_node("Characters/Enemy").alive, "lava filters non-player bodies")
	await screenshot("01_grass_camp")
	await camp_to_ruins()
	await screenshot("02_stone_ruins_checkpoint")
	var cp = current_scene.get_node("Level/Checkpoint_ruins")
	current_scene.get_node("RouteUI/ToastTimer").stop()
	cp._on_body_entered(player)
	check(current_scene.get_node("RouteUI/ToastTimer").is_stopped(), "repeated checkpoint entry does not repeat notification")
	# Visit and return from the optional branch using the same single jump.
	await go(Vector2(9.8, -21))
	await go(Vector2(12.4, -21), true)
	await go(Vector2(9, -21))
	await go(Vector2(0, -20))
	await camera_check()
	await go(Vector2(0, -22.2))
	await go(Vector2(0, -24.8), true)
	await go(Vector2(0, -28.5))
	await camera_check()
	await defeat_guard("RuinsMage")
	await go(Vector2(17, -28.5))
	check(session.checkpoint_id == &"courtyard", "courtyard checkpoint activated by walking")
	await go(Vector2(17, -32))
	await screenshot("03_lava_courtyard_checkpoint")
	await camera_check()
	for pair in [[-34.6, -37.1], [-39.6, -42.1], [-44.6, -47.1], [-49.6, -52.1]]:
		await go(Vector2(17, pair[0]))
		await go(Vector2(17, pair[1]), true)
		if pair[1] == -42.1:
			await defeat_guard("CourtyardMage")
		await camera_check()
		if pair[1] == -42.1:
			# Stage 3 adds a rune gate at the old arena entrance. Preserve
			# every old route assertion, collecting its new required rune
			# on the optional double-jump side challenge before continuing.
			await go(Vector2(21.7, -43))
			await go(Vector2(27, -43), true, true)
			check(&"courtyard" in session.collected_rune_ids, "new side challenge rune collected")
			await go(Vector2(26.3, -43))
			await go(Vector2(21, -43), true, true)
			await go(Vector2(17, -42.1))
	# Stage 4 replaces the reserved arena with a gated encounter. Preserve
	# route/death/retry checks on the safe forecourt, before the battle trigger.
	await go(Vector2(17, -54.7))
	await screenshot("04_reserved_boss_arena")
	check(not player.is_dead, "original main route completed with single jumps; new side challenge uses unlocked double jump")
	await walk_to_death(Vector2.RIGHT)
	for i in 3:
		await retry(&"boss")
		check(current_scene.get_node("Level/Checkpoint_ruins").activated and current_scene.get_node("Level/Checkpoint_courtyard").activated, "both checkpoints remain activated")
		if i < 2:
			await return_to_courtyard()
			await go(Vector2(20.6, -34))
			await walk_to_death(Vector2(0, -1))
			check(player.is_dead and player.position.y > player.fall_death_height, "lava kills above fall threshold")
		print("CONSECUTIVE_CHECKPOINT_RETRY ", i + 1)
	current_scene.get_node("RouteUI/RestartButton").pressed.emit()
	await scene_changed
	player = current_scene.get_node("Characters/Player")
	check(session.checkpoint_id == &"" and player.position.is_equal_approx(Vector3(0, 0.08, 3)), "HUD start over clears checkpoint and restores camp spawn")
	check(not current_scene.get_node("Level/Checkpoint_ruins").activated and not current_scene.get_node("Level/Checkpoint_courtyard").activated, "both checkpoint appearances reset")
	await frames(10)
	# Walk around the now-solid camp tree before testing the map edge.
	await go(Vector2(0, 0))
	await walk_to_death(Vector2.LEFT)
	await retry(&"")
	await camp_to_ruins()
	await walk_to_death(Vector2.LEFT)
	await screenshot("checkpoint_failure_menu")
	await retry(&"ruins")
	check(current_scene.get_node("Level/Checkpoint_ruins").activated, "checkpoint appearance restored after reload")
	await walk_to_death(Vector2.LEFT)
	current_scene.get_node(BUTTONS + "StartOverButton").pressed.emit()
	await scene_changed
	player = current_scene.get_node("Characters/Player")
	check(session.checkpoint_id == &"" and player.position.is_equal_approx(Vector3(0, 0.08, 3)), "failure menu start over also clears checkpoint")
	print("LEVEL_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
