extends Area3D

@export var checkpoint_id: StringName
@export var display_name: String
@export var requires_all_runes := false
var activated := false

func _ready() -> void:
	set_activated(get_node("/root/RunSession").is_activated(checkpoint_id))
	body_entered.connect(_on_body_entered)

func set_activated(value: bool) -> void:
	activated = value
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("57f5bd") if activated else Color("ffc75a")
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.7
	$Beacon.material_override = material
	$Label.text = display_name + ("\n✓ 已激活" if activated else "\n靠近激活检查点")

func _on_body_entered(body: Node3D) -> void:
	if activated or not body.is_in_group("Player") or body.is_dead:
		return
	if requires_all_runes and get_node("/root/RunSession").collected_rune_ids.size() < 3:
		return
	get_node("/root/RunSession").checkpoint_id = checkpoint_id
	set_activated(true)
	get_tree().current_scene.show_checkpoint_message(display_name)
