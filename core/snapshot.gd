@tool
class_name DH_FSM_Snapshot
extends RefCounted
## Point-in-time picture of the project filesystem, built from the editor's
## in-memory EditorFileSystemDirectory tree (no DirAccess walk). Stores mtimes
## for modification diffing and uids for move matching.
## The apply_* methods mirror FileSystemDock-driven changes into the snapshot so
## the next diff sees no delta for them (deduplication).

var file_mtimes: Dictionary[String, int] = {}
var dir_paths: Dictionary[String, bool] = {}
var file_uids: Dictionary[String, int] = {}


static func capture() -> DH_FSM_Snapshot:
	var snapshot: DH_FSM_Snapshot = DH_FSM_Snapshot.new()
	# Fresh get_filesystem() every capture — never cache EditorFileSystemDirectory refs.
	snapshot._walk(EditorInterface.get_resource_filesystem().get_filesystem())
	return snapshot


## Dir paths arrive with a trailing slash from some editor APIs ("res://data/");
## stored and compared without it ("res://data"). The root "res://" keeps its form.
static func normalize_dir_path(dir_path: String) -> String:
	if dir_path.ends_with("/") and dir_path != "res://":
		return dir_path.substr(0, dir_path.length() - 1)
	return dir_path


func apply_file_removal(file_path: String) -> void:
	file_mtimes.erase(file_path)
	file_uids.erase(file_path)


func apply_file_move(from_file_path: String, to_file_path: String) -> void:
	if file_mtimes.has(from_file_path):
		file_mtimes[to_file_path] = file_mtimes[from_file_path]
		file_mtimes.erase(from_file_path)
	if file_uids.has(from_file_path):
		file_uids[to_file_path] = file_uids[from_file_path]
		file_uids.erase(from_file_path)


## Removes the dir, its subdirs and contained files. Returns the file paths it
## actually removed — files the dock already reported one-by-one are gone from
## the snapshot by then, so they don't reappear here.
func apply_dir_removal(dir_path: String) -> PackedStringArray:
	var normalized: String = normalize_dir_path(dir_path)
	var contained_prefix: String = normalized + "/"
	dir_paths.erase(normalized)
	for sub_dir_path: String in dir_paths.keys():
		if sub_dir_path.begins_with(contained_prefix):
			dir_paths.erase(sub_dir_path)
	var removed_file_paths: PackedStringArray = []
	for file_path: String in file_mtimes.keys():
		if file_path.begins_with(contained_prefix):
			removed_file_paths.append(file_path)
			apply_file_removal(file_path)
	return removed_file_paths


## Rewrites the dir, its subdirs and contained files to the new prefix. Returns
## the file moves it actually applied — files the dock already moved one-by-one
## don't reappear here.
func apply_dir_move(from_dir_path: String, to_dir_path: String) -> Array[DH_FSM_Move]:
	var from_normalized: String = normalize_dir_path(from_dir_path)
	var to_normalized: String = normalize_dir_path(to_dir_path)
	var contained_prefix: String = from_normalized + "/"
	if dir_paths.has(from_normalized):
		dir_paths.erase(from_normalized)
		dir_paths[to_normalized] = true
	for sub_dir_path: String in dir_paths.keys():
		if sub_dir_path.begins_with(contained_prefix):
			dir_paths.erase(sub_dir_path)
			dir_paths[to_normalized + "/" + sub_dir_path.trim_prefix(contained_prefix)] = true
	var applied_moves: Array[DH_FSM_Move] = []
	for file_path: String in file_mtimes.keys():
		if file_path.begins_with(contained_prefix):
			var new_file_path: String = to_normalized + "/" + file_path.trim_prefix(contained_prefix)
			apply_file_move(file_path, new_file_path)
			applied_moves.append(DH_FSM_Move.new(file_path, new_file_path))
	return applied_moves


func _walk(dir: EditorFileSystemDirectory) -> void:
	dir_paths[normalize_dir_path(dir.get_path())] = true
	for i: int in dir.get_file_count():
		var file_path: String = dir.get_file_path(i)
		file_mtimes[file_path] = FileAccess.get_modified_time(file_path)
		var uid: int = ResourceLoader.get_resource_uid(file_path)
		if uid != ResourceUID.INVALID_ID:
			file_uids[file_path] = uid
	for i: int in dir.get_subdir_count():
		_walk(dir.get_subdir(i))
