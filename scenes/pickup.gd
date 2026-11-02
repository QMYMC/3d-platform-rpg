extends Area3D

@export_enum("Rune", "DoubleJump", "Health") var kind: int = 0
@export var rune_id: StringName
@export_range(1, 20, 1) var heal_amount: int = 1
var consumed := false

func _ready() -> void:
	# This visual bobs every rendered frame; its pickup area stays stationary.
	$Visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var session := get_node("/root/RunSession")
	if (kind == 0 and rune_id in session.collected_rune_ids) or (kind == 1 and session.double_jump_unlocked):
		queue_free()
		return
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	$Visual.rotation.y += delta * 1.4
	$Visual.position.y = 1.2 + sin(Time.get_ticks_msec() * 0.003) * 0.12

func _on_body_entered(body: Node3D) -> void:
	if consumed or not body.is_in_group("Player") or body.is_dead:
		return
	var session := get_node("/root/RunSession")
	var message: String
	match kind:
		0:
			if not session.collect_rune(rune_id):
				return
			message = "符文已收集 · %d/3 · 集齐后开启庭院门禁" % session.collected_rune_ids.size()
		1:
			if not session.unlock_double_jump():
				return
			message = "二段跳已解锁！跳起后松开，再按空格追加一次跳跃"
		2:
			var previous_health: int = body.health
			if not body.heal(heal_amount):
				return
			message = "恢复 %d 颗心" % (body.health - previous_health)
		_:
			return
	consumed = true
	set_deferred("monitoring", false)
	$Visual.hide()
	$Label.hide()
	set_process(false)
	get_tree().current_scene.show_feedback(message)
	$PickupSound.play()
	await $PickupSound.finished
	queue_free()
