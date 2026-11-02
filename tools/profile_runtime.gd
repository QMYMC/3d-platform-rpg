extends SceneTree

# Diagnostic runner only: no recording unless explicitly requested, and no
# project settings or scene resources are saved by this script.
var samples: Array[float] = []
var cpu: Array[float] = []
var physics: Array[float] = []
var gpu: Array[float] = []
var draw_calls: Array[float] = []
var last_frame := 0
var last_capture := 0
var measuring := false
var readback := false
var motion_camera: Camera3D
var last_camera_position := Vector3.INF
var repeated_camera_frames := 0
var motion_frames := 0

func _initialize() -> void:
	call_deferred("run")

func percentile(values: Array[float], fraction: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(int(sorted.size() * fraction), sorted.size() - 1)]

func sample_frame() -> void:
	var now := Time.get_ticks_usec()
	if measuring and last_frame:
		samples.append((now - last_frame) / 1000.0)
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	last_frame = now
	if readback and now - last_capture > 100000:
		last_capture = now
		var frame := root.get_texture().get_image()
		frame.resize(720, 405, Image.INTERPOLATE_BILINEAR)
	if measuring and is_instance_valid(motion_camera):
		# Retain the diagnostic input if the desktop changes focus mid-sample.
		Input.action_press("forward")
		var position_ := motion_camera.get_global_transform_interpolated().origin
		motion_frames += 1
		if position_.is_equal_approx(last_camera_position):
			repeated_camera_frames += 1
		last_camera_position = position_

func measure(name_: String, warmup := 2.0, duration := 4.0) -> Dictionary:
	await create_timer(warmup).timeout
	samples.clear()
	cpu.clear()
	physics.clear()
	gpu.clear()
	draw_calls.clear()
	measuring = true
	await create_timer(duration).timeout
	measuring = false
	var mean := 0.0
	for value in samples:
		mean += value / samples.size()
	var result := {"view": name_, "frames": samples.size(), "fps": 1000.0 / mean,
		"frame_ms_p50": percentile(samples, 0.5), "frame_ms_p95": percentile(samples, 0.95),
		"frame_ms_p99": percentile(samples, 0.99), "worst_ms": samples.max(),
		"main_process_ms_p50": percentile(cpu, 0.5), "physics_ms_p50": percentile(physics, 0.5),
		"gpu_ms_p50": percentile(gpu, 0.5), "draw_calls_p50": percentile(draw_calls, 0.5)}
	print("PROFILE ", JSON.stringify(result))
	return result

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/performance"))
	var args := OS.get_cmdline_user_args()
	var mode := "baseline"
	for value in args:
		if value.begins_with("--mode="):
			mode = value.trim_prefix("--mode=")
	if mode != "motion_default":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if mode == "motion_raw":
		physics_interpolation = false
	if mode == "motion_interp":
		physics_interpolation = true
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await scene_changed
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	readback = mode == "readback"
	RenderingServer.frame_post_draw.connect(sample_frame)
	var player = current_scene.get_node("Characters/Player")
	if mode.begins_with("motion_"):
		motion_camera = player.get_node("CameraController/Camera3D")
		await create_timer(2).timeout
		Input.action_press("forward")
		var start: Vector3 = player.position
		var result := await measure("camp_forward_movement", 0.3, 2.0)
		Input.action_release("forward")
		result["start_position"] = str(start)
		result["end_position"] = str(player.position)
		result["player_dead"] = player.is_dead
		result["repeated_camera_frame_percent"] = 100.0 * repeated_camera_frames / maxi(motion_frames, 1)
		var output := FileAccess.open("res://test_output/performance/profile_" + mode + ".json", FileAccess.WRITE)
		output.store_string(JSON.stringify({"mode": mode, "interpolation": physics_interpolation, "vsync": DisplayServer.window_get_vsync_mode(), "physics_hz": Engine.physics_ticks_per_second, "screen_hz": DisplayServer.screen_get_refresh_rate(), "view": result}, "\t"))
		print("MOTION ", output.get_path(), " repeat%=", result.repeated_camera_frame_percent, " interpolation=", physics_interpolation)
		print("MOVEMENT ", start, " -> ", player.position, " dead=", player.is_dead)
		quit()
		return
	# Profiling fixtures deliberately select three views; this is not a
	# traversal test. Stop enemies to keep each sample comparable.
	call_group("Enemies", "stop_combat")
	player.set_physics_process(false)
	var results := []
	for view in [["camp", Vector3(0, 0, 3)], ["ruins", Vector3(0, 2, -28.5)], ["arena", Vector3(17, 1, -56.9)]]:
		player.position = view[1]
		results.append(await measure(view[0]))
	var output := FileAccess.open("res://test_output/performance/profile_" + mode + ".json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"mode": mode, "resolution": str(root.size), "vsync": "disabled for measurement", "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(), "views": results}, "\t"))
	quit()
