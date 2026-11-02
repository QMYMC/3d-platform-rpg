extends "res://tests/progression_test.gd"

func screenshot(name_: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://test_output/environment/" + name_ + ".png") == OK, "runtime screenshot: " + name_)

func placement(position_: Vector3) -> void:
	steer(Vector2.ZERO)
	player.position = position_
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await frames(8)

func run() -> void:
	check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "actual main scene loads")
	await scene_changed
	player = current_scene.get_node("Characters/Player")
	session = root.get_node("RunSession")
	await frames(12)
	check(get_nodes_in_group("SolidDecor").size() == 14, "four complete trees and six pillars have fourteen solid parts")
	for body in get_nodes_in_group("SolidDecor"):
		var visual: MeshInstance3D = body.get_parent().get_node(String(body.name).trim_suffix("Collision"))
		var collider: CollisionShape3D = body.get_node("Shape")
		var expected_size := visual.mesh.get_aabb().size * visual.scale
		check(collider.shape is BoxShape3D and collider.shape.size.is_equal_approx(expected_size), "collision fits visible mesh: " + visual.name)
		var center: Vector3 = body.global_position
		var query := PhysicsRayQueryParameters3D.create(center + Vector3.RIGHT * 2, center - Vector3.RIGHT * 2, 1)
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.collider == body, "live physics obstacle: " + visual.name)
	audit_collision()
	steer(Vector2.RIGHT)
	await frames(150)
	steer(Vector2.ZERO)
	check(player.position.x > 4.5 and player.position.x < 5.3, "real input cannot walk through camp tree trunk")
	await placement(Vector3(0, 2, -26))
	steer(Vector2.LEFT)
	await frames(70)
	steer(Vector2.ZERO)
	check(player.position.x > -0.9 and player.position.x < -0.5 and not player.is_dead, "real input cannot walk through ruins pillar")
	await placement(Vector3(0, 2, -28.5))
	await go(Vector2(4.5, -28.5))
	await go(Vector2(4.5, -27))
	await go(Vector2(8.5, -27))
	check(not player.is_dead, "turning main road remains clear between pillars")
	var shot = load("res://scenes/magic_projectile.tscn").instantiate()
	current_scene.add_child(shot)
	shot.launch(Vector3(5, 3, -27), Vector3(5, 3, -33), player, 30.0)
	await frames(10)
	check(not is_instance_valid(shot), "swept projectile stops at decorative pillar")
	var arm = player.get_node("CameraController")
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_RIGHT
	button.pressed = true
	Input.parse_input_event(button)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(60, 20)
	Input.parse_input_event(motion)
	await frames(3)
	button = InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_RIGHT
	button.pressed = false
	Input.parse_input_event(button)
	check(arm.rotation.y < -0.2 and arm.rotation.x <= arm.max_limit_x, "right-button input rotates camera on physical ticks and keeps pitch limits")
	var yaw: float = arm.rotation.y
	Input.parse_input_event(motion)
	await frames(2)
	check(is_equal_approx(yaw, arm.rotation.y), "released right button prevents camera movement")
	player.die()
	await frames(2)
	check(not arm.is_physics_processing() and not arm.is_processing_input(), "failure freezes physical camera processing and input")
	await retry(&"")
	check(player.get_node("CameraController").is_physics_processing(), "retry restores physical camera processing")
	for name_ in ["RuneCamp", "RuneRuins", "RuneCourtyard", "DoubleJumpUnlock", "HealthCamp", "HealthRuins"]:
		check(current_scene.get_node("Adventure/" + name_ + "/Visual").physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "frame-animated pickup stays smooth: " + name_)
	await single_jump_locked()
	session.unlock_double_jump()
	await double_jump_rules()
	print("ENVIRONMENT_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
