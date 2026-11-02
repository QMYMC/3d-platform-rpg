extends Node3D

var is_open := false

func _ready() -> void:
	var player := get_tree().get_first_node_in_group("Player")
	if player:
		# The translucent field blocks the player, but must not collapse the
		# camera arm when its starting sphere touches the field. Stone frame
		# and terrain remain camera obstacles.
		player.get_node("CameraController").add_excluded_object($Blocker.get_rid())
	get_node("/root/RunSession").progress_changed.connect(_update_gate)
	_update_gate()

func _update_gate() -> void:
	var remaining: int = 3 - get_node("/root/RunSession").collected_rune_ids.size()
	is_open = remaining == 0
	$Barrier.visible = not is_open
	$Blocker/CollisionShape3D.set_deferred("disabled", is_open)
	$Label.text = "符文齐备 · 门禁已开启\n前方为守门者场地" if is_open else "符文门禁 · 还缺 %d 枚\n可回走补取营地与遗迹符文" % remaining
