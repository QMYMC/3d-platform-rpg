extends Node3D

var failed := false
var restarting := false
var outcome: StringName = &"playing"
var boss_result_pending := false

@onready var failure_screen: Control = $FailureUI/FailureScreen

func _ready() -> void:
	$Characters/Player.died.connect(_on_player_died)
	$FailureUI/FailureScreen/CenterContainer/PanelContainer/MarginContainer/Buttons/RetryButton.pressed.connect(_on_retry_pressed)
	$FailureUI/FailureScreen/CenterContainer/PanelContainer/MarginContainer/Buttons/QuitButton.pressed.connect(_on_quit_pressed)
	get_node("/root/RunSession").clock_running = true
	if has_node("BossArena"):
		$BossArena/Boss.defeated.connect(_on_boss_defeated)
		$BossArena/Boss.death_finished.connect(_on_boss_death_finished)
		$BossArena/Boss.status_changed.connect(_update_boss_hud)
		$EndUI/Victory/Center/Panel/Margin/Items/Restart.pressed.connect(_on_start_over_pressed)
		$EndUI/Victory/Center/Panel/Margin/Items/Quit.pressed.connect(_on_quit_pressed)
		_update_boss_hud()
	if has_node("Level"):
		$RouteUI/RestartButton.pressed.connect(_on_start_over_pressed)
		$FailureUI/FailureScreen/CenterContainer/PanelContainer/MarginContainer/Buttons/StartOverButton.pressed.connect(_on_start_over_pressed)
		var saved_id: StringName = get_node("/root/RunSession").checkpoint_id
		for checkpoint in get_tree().get_nodes_in_group("Checkpoints"):
			if checkpoint.checkpoint_id == saved_id:
				$Characters/Player.global_transform = checkpoint.get_node("Spawn").global_transform
				$Characters/Player.reset_physics_interpolation()
				$RouteUI/Status.text = "当前检查点：" + checkpoint.display_name
				break
		get_node("/root/RunSession").progress_changed.connect(_update_progress_hud)
		_update_progress_hud()

func _update_progress_hud() -> void:
	var session := get_node("/root/RunSession")
	$RouteUI/Runes.text = "符文 %d/3" % session.collected_rune_ids.size()
	$RouteUI/Ability.text = "二段跳：空中再按一次空格" if session.double_jump_unlocked else "二段跳：前往遗迹主路解锁"

func show_feedback(message: String) -> void:
	if not has_node("RouteUI"):
		return
	$RouteUI/Toast.text = message
	$RouteUI/Toast.show()
	$RouteUI/ToastTimer.start()

func show_checkpoint_message(checkpoint_name: String) -> void:
	$RouteUI/Status.text = "当前检查点：" + checkpoint_name
	show_feedback("检查点已激活 · 失败后从这里重试")

func _on_start_over_pressed() -> void:
	get_node("/root/RunSession").reset_progress()
	_on_retry_pressed()

func _on_player_died() -> void:
	if outcome != &"playing":
		return
	outcome = &"failed"
	failed = true
	var session := get_node("/root/RunSession")
	session.clock_running = false
	session.death_count += 1
	_stop_all_combat()
	if has_node("BossArena"):
		$BossArena.set_barrier(false)
	failure_screen.show()
	$FailureUI/FailureScreen/CenterContainer/PanelContainer/MarginContainer/Buttons/RetryButton.grab_focus()

func _stop_all_combat() -> void:
	get_tree().call_group("Enemies", "stop_combat")
	get_tree().call_group("EnemyProjectiles", "cancel")

func _on_boss_defeated() -> void:
	if outcome != &"playing" or boss_result_pending:
		return
	boss_result_pending = true
	# Decide after every physics contact in this frame, including a final
	# projectile hit. Do not make the player invulnerable before this point.
	get_tree().process_frame.connect(_resolve_boss_result, CONNECT_ONE_SHOT)

func _resolve_boss_result() -> void:
	if outcome != &"playing":
		return
	if $Characters/Player.is_dead or $Characters/Player.health <= 0:
		_on_player_died()
		return
	outcome = &"winning"
	get_node("/root/RunSession").clock_running = false
	_stop_all_combat()
	$BossArena.set_barrier(false)
	$Characters/Player.finish_adventure()
	failure_screen.hide()
	if $BossArena/Boss.death_animation_finished:
		_on_boss_death_finished()

func _on_boss_death_finished() -> void:
	if outcome != &"winning":
		return
	outcome = &"won"
	var session := get_node("/root/RunSession")
	var seconds := int(session.elapsed_seconds)
	$EndUI/Victory/Center/Panel/Margin/Items/Stats.text = "本局用时  %02d:%02d\n死亡次数  %d\n符文收集  %d/3" % [seconds / 60, seconds % 60, session.death_count, session.collected_rune_ids.size()]
	$EndUI/Victory.show()
	$EndUI/Victory/Center/Panel/Margin/Items/Restart.grab_focus()

func _update_boss_hud() -> void:
	if not has_node("BossArena"):
		return
	var boss = $BossArena/Boss
	$BossUI/Bar.visible = $BossArena.battle_started
	$BossUI/Bar/Name.text = "战斧守门者  %s  %d/%d" % ["♥".repeat(boss.health), boss.health, boss.max_health]
	$BossUI/Bar/Status.text = boss.status_text()
	$BossUI/Bar/Status.modulate = Color("78ffad") if boss.state == boss.State.VULNERABLE else Color("ffb099") if boss.state == boss.State.WINDUP else Color.WHITE

func _on_retry_pressed() -> void:
	if restarting:
		return
	restarting = true
	# Reload outside the button/physics callback; all scene state starts afresh.
	call_deferred("_reload_level")

func _reload_level() -> void:
	var error := get_tree().reload_current_scene()
	if error != OK:
		restarting = false
		push_error("无法重新加载关卡：%s" % error_string(error))

func _on_quit_pressed() -> void:
	get_tree().quit()
