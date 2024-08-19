@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_custom_type("DynamicWater2D", "Node2D", preload("water.gd"), preload("dynamic_water_2d.svg"))


func _exit_tree() -> void:
	remove_custom_type("DynamicWater2D")
