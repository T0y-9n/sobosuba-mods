extends Node2D

## A short line between the two balls whose numbers just swapped.

var first: Variant
var second: Variant
var life := 0.35


func _process(delta: float) -> void:
	life -= delta
	queue_redraw()
	if life <= 0.0:
		queue_free()


func _draw() -> void:
	var left: Variant = first.get_ref() if first is WeakRef else null
	var right: Variant = second.get_ref() if second is WeakRef else null
	if left is Node2D and right is Node2D and is_instance_valid(left) and is_instance_valid(right):
		var faded := Color(1.0, 1.0, 1.0, clampf(life / 0.35, 0.0, 1.0))
		draw_line(to_local(left.global_position), to_local(right.global_position), faded, 2.0)
