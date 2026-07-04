@tool
class_name DH_FSM_ChangeSet
extends RefCounted
## Everything one diff pass (or one FileSystemDock event) found. Consumed whole
## via DH_FileSystemMonitorPlugin.changes_detected.

enum EditorContext {UNKNOWN, EDITOR, EXTERNAL}

## EDITOR when this set came from a FileSystemDock signal (editor-driven remove/
## move). UNKNOWN for diff-detected sets: Godot exposes no editor-side signal for
## creates/saves, so a diff can't tell editor from external origin. EXTERNAL is
## reserved for a future source that can prove it (e.g. a focus-in heuristic).
## Dock-driven sets are homogeneous, so one field on the set replaces a
## per-signal editor_context parameter.
var editor_context: EditorContext = EditorContext.UNKNOWN

var created_file_paths: PackedStringArray = []
var created_dir_paths: PackedStringArray = []
var modified_file_paths: PackedStringArray = []
var deleted_file_paths: PackedStringArray = []
var deleted_dir_paths: PackedStringArray = []
var moved_files: Array[DH_FSM_Move] = []


func is_empty() -> bool:
	return created_file_paths.is_empty() and created_dir_paths.is_empty() \
			and modified_file_paths.is_empty() and deleted_file_paths.is_empty() \
			and deleted_dir_paths.is_empty() and moved_files.is_empty()


func _to_string() -> String:
	var lines: PackedStringArray = []
	_append_path_lines(lines, "created dir", created_dir_paths)
	_append_path_lines(lines, "created", created_file_paths)
	_append_path_lines(lines, "modified", modified_file_paths)
	for move: DH_FSM_Move in moved_files:
		lines.append("	moved: %s -> %s" % [move.from_path, move.to_path])
	_append_path_lines(lines, "deleted", deleted_file_paths)
	_append_path_lines(lines, "deleted dir", deleted_dir_paths)
	return "ChangeSet(editor_context=%s):\n%s" % [EditorContext.find_key(editor_context), "\n".join(lines)]


func _append_path_lines(lines: PackedStringArray, label: String, paths: PackedStringArray) -> void:
	for path: String in paths:
		lines.append("	%s: %s" % [label, path])
