extends SceneTree

# Run against the existing main scene:
# Godot --headless --path <project> --script res://tests/player_test.gd
# Omit --headless and append -- --visual to inspect the failure screen.
# In visual mode, a retry is followed by a test-induced fall after 10 seconds.
var failures := 0
var checks := 0
const BUTTONS = "FailureUI/FailureScreen/CenterContainer/PanelContainer/MarginContainer/Buttons/"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/player"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/level"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/progression"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/mages"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/boss"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/environment"))
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
	else:
		print("PASS: ", description)

func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func check_initial(game: Node, spawn: Transform3D, enemy_spawn: Transform3D) -> void:
	var player = game.get_node("Characters/Player")
	var enemy = game.get_node("Characters/Enemy")
	check(player.health == player.max_health and not player.is_dead, "initial health restored")
	check(player.get_node("UI/HFlowContainer").get_child_count() == player.max_health, "initial heart count restored")
	check(player.transform.is_equal_approx(spawn), "authored player spawn restored")
	check(player.velocity == Vector3.ZERO and player.get_node("HitTimer").is_stopped(), "player velocity and hit timer reset")
	check(player.get_node("CameraController").is_processing_input(), "camera input restored")
	check(enemy.alive and enemy.combat_active and not enemy.can_damage and not enemy.has_hit_this_attack, "enemy combat flags restored")
	check(enemy.transform.is_equal_approx(enemy_spawn) and enemy.velocity == Vector3.ZERO, "enemy spawn and velocity restored")
	check(not enemy.get_node("CollisionShape3D").disabled, "enemy collision restored")
	check(not enemy.get_node("AttackTimer").is_stopped() and enemy.get_node("AttackTimer").wait_time == 5.0, "enemy attack timer restarted with initial interval")
	check(enemy.get_node("AnimationTree").get("parameters/DeathBlend/blend_amount") == 0.0, "enemy death animation reset")
	check(not game.failed and not game.get_node("FailureUI/FailureScreen").visible, "failure screen hidden after reload")

func check_failure(game: Node) -> void:
	var player = game.get_node("Characters/Player")
	var enemy = game.get_node("Characters/Enemy")
	check(player.is_dead and player.health == 0 and game.failed, "failure entered once")
	check(player.get_node("UI/HFlowContainer").get_child_count() == 0, "zero hearts on failure")
	check(game.get_node("FailureUI/FailureScreen").visible, "failure screen visible")
	check(game.get_node(BUTTONS + "RetryButton").has_focus(), "retry receives keyboard focus")
	check(player.get_node("HitTimer").is_stopped() and enemy.get_node("AttackTimer").is_stopped(), "combat timers stopped on failure")
	check(not enemy.combat_active and not enemy.can_damage, "enemy damage disabled on failure")
	check(not player.get_node("CameraController").is_processing_input(), "camera input stopped on failure")
	var player_position: Vector3 = player.position
	var enemy_position: Vector3 = enemy.position
	Input.action_press("right")
	Input.action_press("jump")
	enemy._on_attack_timer_timeout()
	enemy.can_damage = true
	player.hit()
	await frames(5)
	Input.action_release("right")
	Input.action_release("jump")
	check(player.position == player_position and player.velocity == Vector3.ZERO, "movement and jump ignored after death")
	check(enemy.position == enemy_position and not enemy.can_damage and not enemy.get_node("SwordSound").playing, "enemy cannot move, attack or play sword audio after failure")

func run() -> void:
	check(change_scene_to_file("res://scenes/test_level.tscn") == OK, "preserved stage one test scene loads")
	await scene_changed
	var game = current_scene
	var player = game.get_node("Characters/Player")
	var enemy = game.get_node("Characters/Enemy")
	var spawn: Transform3D = player.transform
	var enemy_spawn: Transform3D = enemy.transform
	check_initial(game, spawn, enemy_spawn)
	await frames(30)
	check(player.is_on_floor(), "player lands on existing map")
	var start: Vector3 = player.position
	Input.action_press("right")
	await frames(12)
	Input.action_release("right")
	check(player.position.distance_to(start) > 0.3, "normal movement via input works")
	Input.action_press("jump")
	await frames(1)
	Input.action_release("jump")
	check(player.velocity.y > 0.0 and player.get_node("JumpSound").playing, "normal jump and jump sound work")
	player.hit()
	check(player.health == player.max_health - 1 and player.get_node("HitSound").playing, "nonlethal damage and hit sound work")
	player.hit()
	check(player.health == player.max_health - 1, "hit timer prevents repeated immediate damage")
	await frames(2)
	check(player.get_node("AnimationTree").get("parameters/HitOneShot/active"), "hit animation is active")
	await frames(40)
	player.global_position = enemy.global_position + Vector3(0, 4, 0)
	player.velocity = Vector3(0, -4, 0)
	var bounced := false
	for i in 90:
		await frames(1)
		if not enemy.alive and player.velocity.y > 0:
			bounced = true
			break
	check(bounced, "physical fall onto enemy triggers stomp and rebound")
	await frames(2)
	check(not enemy.alive and enemy.get_node("CollisionShape3D").disabled, "defeated enemy collision disabled")
	var ray := PhysicsRayQueryParameters3D.create(enemy.global_position + Vector3.UP * 4, enemy.global_position, 4)
	check(player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "physics ray no longer hits defeated enemy")
	enemy._on_attack_timer_timeout()
	enemy.can_damage = true
	check(enemy.get_node("AttackTimer").is_stopped() and not enemy.can_damage and not enemy.get_node("SwordSound").playing, "defeated enemy cannot restart attack or sword audio")
	await frames(35)
	check(is_equal_approx(enemy.get_node("AnimationTree").get("parameters/DeathBlend/blend_amount"), 1.0), "enemy death blend completes")
	player.hit()
	await check_failure(game)
	await frames(2)
	check(player.get_node("AnimationTree").get("parameters/HitOneShot/active"), "lethal hit animation keeps playing")

	# Three consecutive retries through the actual button signal. Alternate
	# lethal damage and falling; mutate the live enemy before each new failure.
	for retry in 3:
		game.get_node(BUTTONS + "RetryButton").pressed.emit()
		await scene_changed
		game = current_scene
		player = game.get_node("Characters/Player")
		enemy = game.get_node("Characters/Enemy")
		check_initial(game, spawn, enemy_spawn)
		print("RETRY ", retry + 1, " restored correctly")
		await frames(30)
		enemy.global_position = player.global_position + Vector3(1.5, 0, 0)
		enemy._on_attack_timer_timeout()
		await frames(1)
		check(enemy.get_node("AnimationTree").get("parameters/AttackOneShot/active"), "living enemy attack animation still starts")
		if retry % 2 == 0:
			player.global_position.y = player.fall_death_height - 1
			await frames(2)
			check(player.is_dead, "falling below Inspector threshold triggers failure")
		else:
			for i in 90:
				await frames(1)
				if player.health < player.max_health:
					break
			check(player.health == player.max_health - 1, "living enemy still damages player")
			await frames(40)
			player.hit()
		await check_failure(game)

	print("PLAYER_RESULT checks=", checks, " failures=", failures)
	if failures == 0 and "--visual" in OS.get_cmdline_user_args():
		scene_changed.connect(_preview_fall_after_reload)
		print("READY_FOR_UI_CHECK: retry, then wait 10 seconds for another failure; quit with the UI button.")
		return
	quit(0 if failures == 0 else 1)

func _preview_fall_after_reload() -> void:
	print("VISUAL_RETRY: health=", current_scene.get_node("Characters/Player").health,
		" hearts=", current_scene.get_node("Characters/Player/UI/HFlowContainer").get_child_count())
	await create_timer(10.0).timeout
	current_scene.get_node("Characters/Player").global_position.y = current_scene.get_node("Characters/Player").fall_death_height - 1
