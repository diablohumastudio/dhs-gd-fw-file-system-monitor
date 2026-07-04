@tool
class_name DH_FSM_SnapshotDiffer
extends RefCounted
## Compares two snapshots. A deletion and a creation sharing a ResourceUID are
## re-paired into a single move, mirroring the engine-proposal semantics
## ("pre-match pairs of removals and additions based on ResourceUID").


static func diff(old_snapshot: DH_FSM_Snapshot, new_snapshot: DH_FSM_Snapshot) -> DH_FSM_ChangeSet:
	var changes: DH_FSM_ChangeSet = DH_FSM_ChangeSet.new()
	_diff_files(old_snapshot, new_snapshot, changes)
	_diff_dirs(old_snapshot, new_snapshot, changes)
	_repair_moves(old_snapshot, new_snapshot, changes)
	return changes


static func _diff_files(old_snapshot: DH_FSM_Snapshot, new_snapshot: DH_FSM_Snapshot, changes: DH_FSM_ChangeSet) -> void:
	for file_path: String in new_snapshot.file_mtimes:
		if not old_snapshot.file_mtimes.has(file_path):
			changes.created_file_paths.append(file_path)
		elif new_snapshot.file_mtimes[file_path] != old_snapshot.file_mtimes[file_path]:
			changes.modified_file_paths.append(file_path)
	for file_path: String in old_snapshot.file_mtimes:
		if not new_snapshot.file_mtimes.has(file_path):
			changes.deleted_file_paths.append(file_path)


static func _diff_dirs(old_snapshot: DH_FSM_Snapshot, new_snapshot: DH_FSM_Snapshot, changes: DH_FSM_ChangeSet) -> void:
	for dir_path: String in new_snapshot.dir_paths:
		if not old_snapshot.dir_paths.has(dir_path):
			changes.created_dir_paths.append(dir_path)
	for dir_path: String in old_snapshot.dir_paths:
		if not new_snapshot.dir_paths.has(dir_path):
			changes.deleted_dir_paths.append(dir_path)


# deleted + created with the same uid  ==>  one moved_files entry instead.
static func _repair_moves(old_snapshot: DH_FSM_Snapshot, new_snapshot: DH_FSM_Snapshot, changes: DH_FSM_ChangeSet) -> void:
	var created_path_by_uid: Dictionary[int, String] = {}
	for file_path: String in changes.created_file_paths:
		var uid: int = new_snapshot.file_uids.get(file_path, ResourceUID.INVALID_ID)
		if uid != ResourceUID.INVALID_ID:
			created_path_by_uid[uid] = file_path

	var surviving_deleted: PackedStringArray = []
	for deleted_path: String in changes.deleted_file_paths:
		var uid: int = old_snapshot.file_uids.get(deleted_path, ResourceUID.INVALID_ID)
		if uid != ResourceUID.INVALID_ID and created_path_by_uid.has(uid):
			var new_path: String = created_path_by_uid[uid]
			changes.moved_files.append(DH_FSM_Move.new(deleted_path, new_path))
			changes.created_file_paths.remove_at(changes.created_file_paths.find(new_path))
		else:
			surviving_deleted.append(deleted_path)
	changes.deleted_file_paths = surviving_deleted
