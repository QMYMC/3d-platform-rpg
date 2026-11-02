extends "res://tests/level_test.gd"

# Main playthroughs use real player Input actions and collision callbacks.
# Fixtures only add a stationary enemy and an extra high-dose healing bottle;
# player transforms, velocities and progression are never assigned by tests.
class TakeoffProbe extends Node:
	var target: CharacterBody3D
	var samples: Array[float] = []

	func _physics_process(_delta: float) -> void:
		samples.append(target.velocity.y)

func press_first_jump() -> float:
	# A rendered frame may contain multiple physics ticks. Record after the
	# player on each physics tick instead of sampling a later render frame.
	var probe := TakeoffProbe.new()
	probe.target = player
	current_scene.add_child(probe)
	Input.action_press("jump")
	await frames(1)
	var takeoff := 0.0
	for sample in probe.samples:
		if sample > 0:
			takeoff = sample
			break
	probe.queue_free()
	return takeoff

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await frames(2)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://test_output/progression/" + name + ".png") == OK, "screenshot: " + name)

func progress(expected: Array, ability: bool, checkpoint: StringName) -> void:
	check(session.collected_rune_ids.size() == expected.size(), "unique rune count is " + str(expected.size()))
	for id in expected:
		check(id in session.collected_rune_ids, "saved rune retained: " + str(id))
	check(session.double_jump_unlocked == ability, "ability matches saved progress")
	check(session.checkpoint_id == checkpoint, "checkpoint matches saved progress")
	check(current_scene.get_node("RouteUI/Runes").text == "符文 %d/3" % expected.size(), "HUD reflects saved rune count")
	var gate = current_scene.get_node("Adventure/Gate")
	check(gate.is_open == (expected.size() == 3), "gate state matches rune count")
	check(gate.get_node("Blocker/CollisionShape3D").disabled == gate.is_open, "gate physical collision matches visible state")
	if not gate.is_open:
		check(str(3 - expected.size()) in gate.get_node("Label").text, "gate displays missing rune count")

func start_over(button_path: String) -> void:
	current_scene.get_node(button_path).pressed.emit()
	await scene_changed
	player = current_scene.get_node("Characters/Player")
	await frames(5)
	progress([], false, &"")
	check(session.death_count == 0 and session.elapsed_seconds < 0.5 and session.clock_running, "start over clears run statistics through the shared reset")
	check(player.health == player.max_health and player.position.distance_to(Vector3(0, 0, 3)) < 0.2, "start over restores safe camp spawn and full health")
	for path in ["RuneCamp", "RuneRuins", "RuneCourtyard", "DoubleJumpUnlock", "HealthCamp", "HealthRuins"]:
		check(current_scene.has_node("Adventure/" + path), "start over restores " + path)

func single_jump_locked() -> void:
	var takeoff: float = await press_first_jump()
	check(is_equal_approx(takeoff, player.jump_strength), "first jump retains original takeoff velocity")
	await frames(12)
	Input.action_release("jump")
	await frames(1)
	var before: float = player.velocity.y
	Input.action_press("jump")
	await frames(1)
	Input.action_release("jump")
	check(player.velocity.y < before and not player.get_node("AirJumpSound").playing, "locked ability rejects airborne jump")
	await frames(70)
	check(player.is_on_floor(), "normal landing still works")

func double_jump_rules() -> void:
	var takeoff: float = await press_first_jump()
	check(is_equal_approx(takeoff, player.jump_strength), "unlocked first jump keeps the same velocity")
	await frames(12)
	check(player.air_jump_available and not player.get_node("AirJumpRing").visible, "holding first jump does not consume an air jump")
	Input.action_release("jump")
	await frames(1)
	Input.action_press("jump")
	await frames(1)
	check(player.velocity.y > 0 and player.velocity.y <= player.double_jump_strength and not player.air_jump_available, "second press applies Inspector strength and consumes the air jump")
	check(player.get_node("AirJumpSound").playing and player.get_node("AirJumpRing").visible, "second jump has distinct audio and visible ring")
	# Read before synchronous screenshot I/O can consume the short flash.
	var flash_time: float = player.get_node("AirJumpFlash").time_left
	await screenshot("03_air_jump_feedback")
	await frames(4)
	check(player.get_node("AirJumpFlash").time_left < flash_time, "holding jump does not retrigger feedback")
	Input.action_release("jump")
	await frames(1)
	var before: float = player.velocity.y
	Input.action_press("jump")
	await frames(1)
	Input.action_release("jump")
	check(player.velocity.y < before and not player.air_jump_available, "third airborne press cannot jump")
	await frames(90)
	check(player.is_on_floor() and player.air_jump_available, "landing restores one air jump")
	var enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.name = "StompFixture"
	enemy.notice_radius = 0
	enemy.position = player.position + Vector3(0, 0.08, 1.5)
	current_scene.get_node("Characters").add_child(enemy)
	enemy.get_node("AttackTimer").stop()
	Input.action_press("jump")
	await frames(1)
	Input.action_release("jump")
	await frames(23)
	steer(Vector2(0, 1))
	Input.action_press("jump")
	await frames(1)
	Input.action_release("jump")
	check(not player.air_jump_available, "air jump spent before stomp")
	await frames(29)
	steer(Vector2.ZERO)
	var stomped := false
	for i in 100:
		await frames(1)
		if not enemy.alive:
			stomped = true
			break
	check(stomped and player.velocity.y > 0 and player.air_jump_available, "real stomp rebound restores one air jump")
	Input.action_press("jump")
	await frames(1)
	Input.action_release("jump")
	check(player.velocity.y > 0 and not player.air_jump_available, "restored post-stomp air jump is usable once")
	await frames(100)
	enemy.queue_free()
	await frames(2)

func healing_rules() -> void:
	await go(Vector2(-2.5, -3))
	var bottle = current_scene.get_node("Adventure/HealthCamp")
	check(not bottle.consumed and player.health == player.max_health, "full health leaves bottle unconsumed")
	bottle._on_body_entered(current_scene.get_node("Characters/Enemy"))
	check(not bottle.consumed, "enemy cannot consume healing bottle")
	player.hit()
	check(player.health == player.max_health - 1, "existing hit flow deals one damage")
	await go(Vector2(-2.5, -0.5))
	await go(Vector2(-2.5, -3))
	check(player.health == player.max_health, "real reentry consumes bottle and restores one heart")
	await frames(40)
	check(not current_scene.has_node("Adventure/HealthCamp"), "consumed healing bottle disappears")
	player.hit()
	var strong = load("res://scenes/health_pickup.tscn").instantiate()
	strong.heal_amount = 20
	strong.position = player.position
	current_scene.add_child(strong)
	await frames(5)
	check(player.health == player.max_health and player.get_node("UI/HFlowContainer").get_child_count() == player.max_health, "healing amount is clamped to maximum health and hearts")
	await frames(30)

func ruins_to_courtyard() -> void:
	var already_unlocked: bool = session.double_jump_unlocked
	await go(Vector2(0, -22.2))
	await go(Vector2(0, -24.8), true)
	await go(Vector2(0, -28.5))
	await defeat_guard("RuinsMage")
	await go(Vector2(8.5, -28.5))
	await go(Vector2(10, -28.5))
	check(session.double_jump_unlocked, "main-road unlock activates before courtyard checkpoint")
	if not already_unlocked:
		await screenshot("02_unlock_hint")

func to_high_platform() -> void:
	await go(Vector2(17, -34.6))
	await go(Vector2(17, -37.1), true)
	await go(Vector2(17, -39.6))
	await go(Vector2(17, -42.1), true)
	await defeat_guard("CourtyardMage")

func collect_courtyard() -> void:
	await go(Vector2(21.7, -43))
	await screenshot("04_double_jump_challenge")
	await go(Vector2(27, -43), true, true)
	check(&"courtyard" in session.collected_rune_ids, "double jump crosses wide gap to rune platform")
	await screenshot("05_all_runes_hud")
	await go(Vector2(26.3, -43))
	await go(Vector2(21, -43), true, true)
	await go(Vector2(17, -42.1))

func to_gate() -> void:
	await go(Vector2(17, -44.6))
	await go(Vector2(17, -47.1), true)
	await go(Vector2(17, -49.6))
	await go(Vector2(17, -52.1), true)

func back_to_checkpoint() -> void:
	await go(Vector2(17, -51.4))
	await go(Vector2(17, -48.9), true)
	await go(Vector2(17, -46.4))
	await go(Vector2(17, -43.9), true)
	await go(Vector2(17, -41.4))
	await go(Vector2(17, -38.9), true)
	await go(Vector2(17, -36.4))
	await go(Vector2(17, -33.9), true)
	await go(Vector2(17, -29))

func back_to_ruins() -> void:
	await go(Vector2(13.8, -28.5))
	await go(Vector2(11.2, -28.5), true)
	await defeat_guard("RuinsMage")
	await go(Vector2(0, -28.5))
	await go(Vector2(0, -24.8))
	await go(Vector2(0, -20))

func collect_ruins() -> void:
	await go(Vector2(9.8, -21))
	await go(Vector2(12.4, -21), true)
	check(&"ruins" in session.collected_rune_ids, "ruins exploration branch rune collected by movement")
	await go(Vector2(9, -21))
	await go(Vector2(0, -20))

func closed_gate_camera() -> void:
	check(player.get_node("CameraController").get_hit_length() > 3.0, "closed energy field does not collapse camera arm")
	check(not current_scene.get_node("Adventure/Gate/Blocker/CollisionShape3D").disabled, "camera exclusion preserves player gate collision")
	await screenshot("06_gate_closed")

func gate_camera_test() -> void:
	check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "configured main scene loads")
	await scene_changed
	player = current_scene.get_node("Characters/Player")
	session = root.get_node("RunSession")
	await frames(20)
	await camp_to_ruins()
	await ruins_to_courtyard()
	await go(Vector2(17, -29))
	await to_high_platform()
	await to_gate()
	steer(Vector2(0, -1))
	await frames(45)
	steer(Vector2.ZERO)
	check(player.position.z > -54, "closed gate still blocks forward movement")
	progress([&"camp"], true, &"courtyard")
	await closed_gate_camera()
	print("GATE_CAMERA_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func run() -> void:
	if "--gate-camera" in OS.get_cmdline_user_args():
		await gate_camera_test()
		return
	check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "configured main scene loads")
	await scene_changed
	player = current_scene.get_node("Characters/Player")
	session = root.get_node("RunSession")
	await frames(20)
	progress([], false, &"")
	await screenshot("00_clean_hud")
	await single_jump_locked()
	# The camp tree is solid; approach an unobstructed edge for this fall test.
	await go(Vector2(0, 0))
	await walk_to_death(Vector2.LEFT)
	await retry(&"")
	progress([], false, &"")
	await healing_rules()
	await go(Vector2(0, -3))
	check(session.collected_rune_ids == [&"camp"], "camp rune introduces collection goal")
	check(not session.collect_rune(&"camp") and session.collected_rune_ids.size() == 1, "duplicate rune ID cannot increment count")
	await screenshot("01_rune_hud")
	await walk_to_death(Vector2.LEFT)
	check(not player.heal(1), "dead player cannot heal")
	current_scene.get_node("Adventure/HealthRuins")._on_body_entered(player)
	check(not current_scene.get_node("Adventure/HealthRuins").consumed, "dead player cannot consume bottle")
	await retry(&"")
	progress([&"camp"], false, &"")
	check(not current_scene.has_node("Adventure/RuneCamp") and current_scene.has_node("Adventure/HealthCamp"), "reload hides saved rune and respawns healing bottle")
	await camp_to_ruins()
	await ruins_to_courtyard()
	await double_jump_rules()
	await go(Vector2(10, -28.5))
	await go(Vector2(17, -29))
	progress([&"camp"], true, &"courtyard")
	await to_high_platform()
	# Four-metre gap exceeds the original single-jump horizontal range,
	# including the capsule's edge support. Try it without the air jump.
	await go(Vector2(21.7, -43))
	steer(Vector2.RIGHT)
	Input.action_press("jump")
	await frames(1)
	Input.action_release("jump")
	for i in 150:
		await frames(1)
		if player.is_dead:
			break
	steer(Vector2.ZERO)
	check(&"courtyard" not in session.collected_rune_ids and player.is_dead, "single jump cannot collect courtyard rune")
	await retry(&"courtyard")
	progress([&"camp"], true, &"courtyard")
	await to_high_platform()
	await to_gate()
	steer(Vector2(0, -1))
	await frames(45)
	steer(Vector2.ZERO)
	check(player.position.z > -54 and not current_scene.get_node("Adventure/Gate").is_open, "closed gate physically blocks arena entrance")
	await closed_gate_camera()
	await back_to_checkpoint()
	await back_to_ruins()
	await collect_ruins()
	await ruins_to_courtyard()
	await go(Vector2(17, -29))
	await to_high_platform()
	await collect_courtyard()
	progress([&"camp", &"ruins", &"courtyard"], true, &"courtyard")
	await to_gate()
	await go(Vector2(17, -55))
	await screenshot("07_gate_open")
	await go(Vector2(17, -54.7))
	check(not current_scene.failed and not player.is_dead and not current_scene.get_node("BossArena").battle_started, "open rune gate leads to safe boss forecourt, not premature completion")
	await walk_to_death(Vector2.RIGHT)
	await retry(&"boss")
	progress([&"camp", &"ruins", &"courtyard"], true, &"boss")
	for name in ["RuneCamp", "RuneRuins", "RuneCourtyard", "DoubleJumpUnlock"]:
		check(not current_scene.has_node("Adventure/" + name), "saved pickup stays absent after retry: " + name)
	await start_over("RouteUI/RestartButton")
	# New clean run: deliberately miss both earlier runes, take the branch
	# shortcut to prove the unlock cannot be skipped before checkpoint two.
	await go(Vector2(-2, -8))
	await go(Vector2(0, -9.6))
	await go(Vector2(0, -12.1), true)
	await go(Vector2(0, -20))
	await go(Vector2(9.8, -22.6))
	await go(Vector2(12.4, -23), true)
	await go(Vector2(15.4, -23.4))
	await go(Vector2(16.3, -26.1), true)
	await go(Vector2(17, -29))
	progress([], true, &"courtyard")
	check(session.double_jump_unlocked, "branch shortcut also unlocks ability before checkpoint")
	await go(Vector2(20.6, -34))
	await walk_to_death(Vector2(0, -1))
	await retry(&"courtyard")
	await back_to_ruins()
	await collect_ruins()
	await go(Vector2(0, -11.4))
	await go(Vector2(0, -8.9), true)
	await go(Vector2(0, -3))
	check(&"camp" in session.collected_rune_ids and &"ruins" in session.collected_rune_ids, "both earlier missed runes recoverable from courtyard checkpoint")
	check(session.checkpoint_id == &"courtyard", "backtracking does not downgrade checkpoint")
	await walk_to_death(Vector2.LEFT)
	await retry(&"courtyard")
	progress([&"camp", &"ruins"], true, &"courtyard")
	await to_high_platform()
	await collect_courtyard()
	progress([&"camp", &"ruins", &"courtyard"], true, &"courtyard")
	await walk_to_death(Vector2.RIGHT)
	await start_over(BUTTONS + "StartOverButton")
	print("PROGRESSION_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
