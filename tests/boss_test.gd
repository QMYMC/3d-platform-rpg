extends "res://tests/mage_test.gd"

const VICTORY = "EndUI/Victory/Center/Panel/Margin/Items/"
var boss_contacts: Array[Dictionary] = []
var recording_boss := false

class SameFrameRace extends Node:
	var boss: Node
	var player: Node
	var player_first := false
	var frames_seen: Array[int] = []
	func _physics_process(_delta: float) -> void:
		set_physics_process(false)
		if player_first:
			player.die()
			frames_seen.append(Engine.get_physics_frames())
			boss.defeat()
		else:
			boss.defeat()
			frames_seen.append(Engine.get_physics_frames())
			player.die()
		frames_seen.append(Engine.get_physics_frames())

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await frames(2)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://test_output/boss/" + name + ".png") == OK, "screenshot: " + name)

func capture_clip_frame() -> void:
	var now := Time.get_ticks_msec()
	if not recording_boss or now - last_capture < 100:
		return
	last_capture = now
	var image_ := root.get_texture().get_image()
	image_.resize(720, 405, Image.INTERPOLATE_BILINEAR)
	clip_images.append(image_)
	clip_times.append(now)

func start_boss_clip() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/boss_clip_frames"))
	clip_images.clear()
	clip_times.clear()
	last_capture = 0
	recording_boss = true

func finish_boss_clip() -> void:
	if not recording_boss:
		return
	recording_boss = false
	for i in clip_images.size():
		clip_images[i].save_png("res://.godot/boss_clip_frames/frame_%03d.png" % i)
	clip_images.clear()
	var output := FileAccess.open("res://test_output/boss/clip_frames.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"times_ms": clip_times}))
	check(clip_times.size() > 60, "complete boss battle recorded from real viewport frames")

func record_boss_contact(body: Node3D) -> void:
	if body.is_in_group("Bosses"):
		boss_contacts.append({"health": body.health, "air": player.air_jump_available, "velocity": player.velocity.y})

func main_scene(fixture_progress := false) -> void:
	session = root.get_node("RunSession")
	session.reset_progress()
	if fixture_progress:
		for id in session.RUNE_IDS:
			session.collect_rune(id)
		session.unlock_double_jump()
		session.checkpoint_id = &"boss"
	check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "main scene loads")
	await scene_changed
	player = current_scene.get_node("Characters/Player")
	player.get_node("JumpDetectionArea").body_entered.connect(record_boss_contact)
	await frames(12)

func wait_state(boss: Node, expected: int, max_frames := 1500) -> void:
	for i in max_frames:
		if boss.state == expected:
			return
		await frames(1)
	check(false, "boss did not reach expected state " + str(expected))

func stomp_once(boss: Node) -> void:
	var target := Vector2(boss.global_position.x, boss.global_position.z)
	var away := (Vector2(player.position.x, player.position.z) - target).normalized()
	if away == Vector2.ZERO:
		away = Vector2(0, 1)
	await go(target + away * 2.3)
	var before := boss_contacts.size()
	Input.action_press("jump")
	for i in 160:
		var offset := target - Vector2(player.position.x, player.position.z)
		steer(offset.normalized() * clampf(offset.length() * 3, 0.6, 1) if offset.length() > 0.07 else Vector2.ZERO)
		await frames(1)
		Input.action_release("jump")
		if boss_contacts.size() > before:
			break
	steer(Vector2.ZERO)
	check(boss_contacts.size() > before, "real descending body contact reaches boss head")
	check(boss_contacts[-1].air and boss_contacts[-1].velocity > 0, "boss stomp preserves rebound and air-jump opportunity")
	if boss.health < boss.max_health:
		await screenshot("04_stomp_damage_%d" % boss.health)
	if not boss.alive:
		return
	steer(away)
	await frames(65)
	steer(Vector2.ZERO)
	await frames(5)

func shield_and_window_suite() -> void:
	check(change_scene_to_file("res://scenes/test_level.tscn") == OK, "stomp fixture loads")
	await scene_changed
	player = current_scene.get_node("Characters/Player")
	await frames(20)
	var boss = load("res://scenes/boss.tscn").instantiate()
	boss.position = player.position + Vector3(2.3, 0, 0)
	current_scene.add_child(boss)
	player.get_node("JumpDetectionArea").body_entered.connect(record_boss_contact)
	await stomp_once(boss)
	check(boss.health == 3 and boss.alive, "shielded physical stomp does not directly defeat boss")
	# Window bookkeeping is isolated from the input-driven full battle below.
	boss.combat_active = true
	boss.state = boss.State.ATTACK
	boss._open_window()
	boss.receive_stomp()
	check(boss.health == 2 and boss.state == boss.State.RECOVER, "one vulnerable stomp removes exactly one health")
	boss.receive_stomp()
	check(boss.health == 2, "same-window repeat cannot remove a second health")
	boss.defeat()
	check(boss.alive, "direct defeat cannot bypass remaining boss health")
	boss.stop_combat()
	check(boss.get_node("StateTimer").is_stopped() and boss.get_node("VolleyTimer").is_stopped(), "stop_combat cancels boss timers")
	var imported = load("res://graphics/characters/nagonford/Nagonford_Animated.glb").instantiate()
	check(imported.get_node("AnimationPlayer").get_animation("Idle").loop_mode == Animation.LOOP_NONE, "shared boss import keeps original loop setting")
	check(boss.animator.get_animation("Idle").loop_mode == Animation.LOOP_LINEAR, "boss idle loop is instance-local")
	imported.free()

func lifecycle_suite() -> void:
	await main_scene(true)
	var session_time: float = session.elapsed_seconds
	await frames(30)
	check(session.elapsed_seconds > session_time, "play timer advances while playing")
	for phase in [0, 1, 2]:
		var boss = current_scene.get_node("BossArena/Boss")
		check(boss.health == boss.max_health and boss.state == boss.State.WAITING and not boss.combat_active, "retry starts with full-health idle boss")
		check(player.health == player.max_health and not boss.get_node("StateTimer").time_left, "retry restores full player health and no old state timer")
		for shape in current_scene.get_node("BossArena/BattleBarrier").get_children():
			if shape is CollisionShape3D:
				check(shape.disabled, "retry starts with open battle barrier")
		check(current_scene.get_node("Adventure/Gate").is_open, "rune gate remains independently open")
		await go(Vector2(17, -56.4))
		check(current_scene.get_node("BossArena").battle_started, "input entry starts rune-unlocked encounter")
		if phase == 0:
			await wait_state(boss, boss.State.WINDUP)
		elif phase == 1:
			for i in 1600:
				if boss.state == boss.State.ATTACK and boss.attack_kind == 1:
					break
				await frames(1)
			check(get_nodes_in_group("EnemyProjectiles").size() == 3, "fan attack emits exactly three projectiles")
		else:
			await wait_state(boss, boss.State.VULNERABLE)
		var deaths_before: int = session.death_count
		player.die()
		await frames(3)
		check(current_scene.outcome == &"failed" and current_scene.failed, "phase failure resolves only as failure")
		check(session.death_count == deaths_before + 1, "failure counts once")
		var paused: float = session.elapsed_seconds
		await frames(90)
		check(is_equal_approx(paused, session.elapsed_seconds), "failure screen time is excluded")
		check(get_nodes_in_group("EnemyProjectiles").is_empty() and not boss.combat_active, "failure removes all attacks and projectiles")
		await retry(&"boss")
		player.get_node("JumpDetectionArea").body_entered.connect(record_boss_contact)
		check(session.death_count == deaths_before + 1 and session.collected_rune_ids.size() == 3 and session.double_jump_unlocked, "retry keeps deaths, runes, ability and boss checkpoint")
		check(get_nodes_in_group("EnemyProjectiles").is_empty(), "old projectile never survives reload")
		print("BOSS_RETRY ", phase + 1)

func race_suite() -> void:
	for player_first in [false, true]:
		await main_scene(true)
		var boss = current_scene.get_node("BossArena/Boss")
		boss.health = 0
		var race := SameFrameRace.new()
		race.boss = boss
		race.player = player
		race.player_first = player_first
		current_scene.add_child(race)
		await frames(90)
		check(race.frames_seen.size() == 2 and race.frames_seen[0] == race.frames_seen[1], "both deaths were issued in one physical frame")
		check(not boss.alive and player.is_dead, "race fixture contains both actual deaths")
		check(current_scene.outcome == &"failed" and current_scene.get_node("FailureUI/FailureScreen").visible and not current_scene.get_node("EndUI/Victory").visible, "player death wins in either callback order")

func melee_and_supply_suite() -> void:
	await main_scene(true)
	player.hit()
	await go(Vector2(19, -52.3))
	await go(Vector2(17, -52.3))
	check(player.health == player.max_health, "forecourt supply restores a wounded player to full health")
	await frames(90)
	check(not current_scene.get_node("BossArena").has_node("FullHeal"), "consumed supply is safely removed before battle entry")
	var boss = current_scene.get_node("BossArena/Boss")
	await go(Vector2(17, -56.4))
	var heading: float = boss.rotation.y
	await go(Vector2(17.5, -58.1))
	check(is_equal_approx(heading, boss.rotation.y), "locked attack direction does not follow a moving target")
	await wait_state(boss, boss.State.VULNERABLE)
	check(player.health == player.max_health - 1, "animation-timed melee deals exactly one real hit")
	await frames(45)
	check(player.health == player.max_health - 1 and player.get_node("HitTimer").is_stopped(), "melee cannot re-hit after protection expires")
	boss.stop_combat()
	steer(Vector2(0, 1))
	await frames(120)
	steer(Vector2.ZERO)
	check(player.position.z < -55.5 and current_scene.get_node("Adventure/Gate").is_open, "separate battle barrier blocks escape while rune gate stays open")

func fight() -> void:
	var boss = current_scene.get_node("BossArena/Boss")
	start_boss_clip()
	await go(Vector2(17, -56.9))
	check(boss.state == boss.State.WINDUP, "battle has visible wind-up before damage")
	await screenshot("01_melee_warning")
	var initial_health: int = player.health
	for expected in [2, 1, 0]:
		var moved_for_fan := false
		var captured_flight := false
		for i in 1200:
			if boss.state == boss.State.VULNERABLE:
				break
			if boss.attack_kind == 1 and boss.state == boss.State.WINDUP and not moved_for_fan:
				await screenshot("02_fan_warning")
				await go(Vector2(21, -56.9))
				moved_for_fan = true
			if boss.attack_kind == 1 and boss.state == boss.State.ATTACK and not captured_flight:
				await screenshot("02b_projectile_flight")
				captured_flight = true
			await frames(1)
		check(boss.state == boss.State.VULNERABLE and boss.get_node("WeakRing").visible and not boss.get_node("Shield").visible, "green vulnerability is distinct from shield")
		await screenshot("03_vulnerable")
		await stomp_once(boss)
		check(boss.health == expected, "effective stomp leaves boss health " + str(expected))
		await screenshot("04_stomp_damage")
		if expected > 0:
			var health_before: int = boss.health
			boss.receive_stomp()
			check(boss.health == health_before, "spent window rejects repeated contact")
			await go(Vector2(17, -56.9))
	check(player.health == initial_health, "both telegraphed attacks were dodged through actual movement")
	for i in 120:
		await frames(1)
		if current_scene.outcome == &"won":
			break
	check(current_scene.outcome == &"won" and current_scene.get_node("EndUI/Victory").visible, "boss death animation leads to a single victory screen")
	finish_boss_clip()
	await screenshot("05_victory")
	var final_time: float = session.elapsed_seconds
	var deaths: int = session.death_count
	var health: int = player.health
	var position_: Vector3 = player.position
	player.hit()
	player.die()
	player.died.emit()
	steer(Vector2.RIGHT)
	Input.action_press("jump")
	await frames(90)
	steer(Vector2.ZERO)
	Input.action_release("jump")
	check(player.health == health and not player.is_dead and player.position == position_ and current_scene.outcome == &"won", "victory rejects damage, death and player input")
	check(is_equal_approx(session.elapsed_seconds, final_time) and session.death_count == deaths, "victory freezes timer and death count")
	var stats: String = current_scene.get_node(VICTORY + "Stats").text
	check("3/3" in stats and ("死亡次数  %d" % deaths) in stats, "settlement reports rune count and recorded deaths")
	if "--quit-victory" in OS.get_cmdline_user_args():
		print("VICTORY_QUIT_VERIFIED")
		current_scene.get_node(VICTORY + "Quit").pressed.emit()
		return
	current_scene.get_node(VICTORY + "Restart").pressed.emit()
	await scene_changed
	player = current_scene.get_node("Characters/Player")
	await frames(5)
	check(session.collected_rune_ids.is_empty() and not session.double_jump_unlocked and session.checkpoint_id == &"", "victory replay clears all progression")
	check(session.death_count == 0 and session.elapsed_seconds < 0.5 and session.clock_running, "victory replay resets statistics and restarts timer")
	check(current_scene.outcome == &"playing" and player.control_enabled and player.damage_enabled, "victory replay restores gameplay controls")

func complete_run() -> void:
	await main_scene()
	check(session.checkpoint_id == &"" and session.collected_rune_ids.is_empty(), "real playthrough begins clean")
	await camp_to_ruins()
	await collect_ruins()
	await ruins_to_courtyard()
	await go(Vector2(17, -29))
	await to_high_platform()
	await collect_courtyard()
	await to_gate()
	check(session.checkpoint_id == &"boss" and current_scene.get_node("Adventure/Gate").is_open, "actual collection opens gate and activates safe boss checkpoint")
	var boss = current_scene.get_node("BossArena/Boss")
	check(boss.state == boss.State.WAITING and not boss.combat_active, "boss never attacks on forecourt")
	await go(Vector2(17, -56.4))
	player.die()
	await retry(&"boss")
	player.get_node("JumpDetectionArea").body_entered.connect(record_boss_contact)
	check(session.death_count == 1, "actual route retry is retained in settlement statistics")
	await fight()

func run() -> void:
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(capture_clip_frame)
	if "--play-only" not in OS.get_cmdline_user_args() and "--quit-victory" not in OS.get_cmdline_user_args():
		await shield_and_window_suite()
		await lifecycle_suite()
		await race_suite()
		await melee_and_supply_suite()
	if "--arena-only" in OS.get_cmdline_user_args():
		await main_scene(true)
		await fight()
	else:
		await complete_run()
	print("BOSS_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
