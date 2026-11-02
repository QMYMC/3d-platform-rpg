extends Node3D

var battle_started := false

func _ready() -> void:
	$Entrance.body_entered.connect(_on_entered)
	var player := get_tree().get_first_node_in_group("Player")
	if player:
		player.get_node("CameraController").add_excluded_object($BattleBarrier.get_rid())
	var old_sign := get_tree().current_scene.get_node_or_null("Level/Decoration/FinishSign")
	if old_sign:
		old_sign.hide()
	set_barrier(false)

func _on_entered(body: Node3D) -> void:
	if battle_started or not body.is_in_group("Player") or body.is_dead:
		return
	if get_node("/root/RunSession").collected_rune_ids.size() != 3:
		return
	if get_tree().current_scene.outcome != &"playing":
		return
	battle_started = true
	# These approach-only signs otherwise sit between the camera and boss.
	for path in ["BossArena/EntrySign", "BossArena/Checkpoint_boss/Label", "BossArena/FullHeal/Label", "Adventure/Gate/Label"]:
		var sign := get_tree().current_scene.get_node_or_null(path)
		if sign:
			sign.hide()
	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if enemy != $Boss:
			enemy.stop_combat()
	get_tree().call_group("EnemyProjectiles", "cancel")
	set_barrier(true)
	$Boss.start_battle()
	get_tree().current_scene.show_feedback("守门者开战：红色躲，绿色踩头 · 护盾时踩中仍会反弹")

func set_barrier(enabled: bool) -> void:
	$BattleBarrier/Visuals.visible = enabled
	for shape in $BattleBarrier.get_children():
		if shape is CollisionShape3D:
			shape.set_deferred("disabled", not enabled)
