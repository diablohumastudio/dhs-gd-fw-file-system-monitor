@tool
class_name DH_FSM_Move
extends RefCounted
## A matched from -> to file move within one DH_FSM_ChangeSet.

var from_path: String
var to_path: String


func _init(p_from_path: String, p_to_path: String) -> void:
	from_path = p_from_path
	to_path = p_to_path
