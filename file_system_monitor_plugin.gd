@tool
class_name DH_FileSystemMonitorPlugin
extends EditorPlugin
## Emulates the proposed EditorFileSystem file created/modified/deleted/moved
## signals in GDScript, batched into
## DH_FSM_ChangeSets. One shared snapshot for the whole editor; consumer addons
## reach the monitor via DH_FileSystemMonitorPlugin.instance.

## The single change signal: one emission per diff pass or per dock event, so a
## 20-file paste updates a consumer's UI once, not 20 times.
signal changes_detected(changes: DH_FSM_ChangeSet)
## Re-exposed so consumers need only this plugin. The trailing filesystem_changed
## is NOT suppressed: it just produces a diff whose .gd entries consumers filter
## out, and the diff runs deferred so class maps rebuild before file events arrive.
signal script_classes_updated()

## Prints every emitted ChangeSet to the Output panel. Kept for debugging;
## verified off after the manual test rounds.
const DEBUG_LOGGING: bool = false

static var instance: DH_FileSystemMonitorPlugin

var _snapshot: DH_FSM_Snapshot   # null until _capture_baseline finishes
var _diff_queued: bool = false


func _enter_tree() -> void:
	instance = self
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if not efs.filesystem_changed.is_connected(_on_filesystem_changed):
		efs.filesystem_changed.connect(_on_filesystem_changed)
	if not efs.script_classes_updated.is_connected(_on_efs_script_classes_updated):
		efs.script_classes_updated.connect(_on_efs_script_classes_updated)
	var dock: FileSystemDock = EditorInterface.get_file_system_dock()
	if not dock.file_removed.is_connected(_on_dock_file_removed):
		dock.file_removed.connect(_on_dock_file_removed)
	if not dock.folder_removed.is_connected(_on_dock_folder_removed):
		dock.folder_removed.connect(_on_dock_folder_removed)
	if not dock.files_moved.is_connected(_on_dock_files_moved):
		dock.files_moved.connect(_on_dock_files_moved)
	if not dock.folder_moved.is_connected(_on_dock_folder_moved):
		dock.folder_moved.connect(_on_dock_folder_moved)
	_capture_baseline()


func _exit_tree() -> void:
	if instance == self:
		instance = null
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if efs.filesystem_changed.is_connected(_on_filesystem_changed):
		efs.filesystem_changed.disconnect(_on_filesystem_changed)
	if efs.script_classes_updated.is_connected(_on_efs_script_classes_updated):
		efs.script_classes_updated.disconnect(_on_efs_script_classes_updated)
	var dock: FileSystemDock = EditorInterface.get_file_system_dock()
	if dock.file_removed.is_connected(_on_dock_file_removed):
		dock.file_removed.disconnect(_on_dock_file_removed)
	if dock.folder_removed.is_connected(_on_dock_folder_removed):
		dock.folder_removed.disconnect(_on_dock_folder_removed)
	if dock.files_moved.is_connected(_on_dock_files_moved):
		dock.files_moved.disconnect(_on_dock_files_moved)
	if dock.folder_moved.is_connected(_on_dock_folder_moved):
		dock.folder_moved.disconnect(_on_dock_folder_moved)


## Awaits the initial EFS scan (if any) so the baseline is never captured from a
## partial in-memory tree — that would flood the first diff with false creations.
## Once captured, the very next change IS diffed and reported.
func _capture_baseline() -> void:
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	while efs.is_scanning():
		await get_tree().process_frame
	if not is_inside_tree():
		return   # plugin was disabled while awaiting
	_snapshot = DH_FSM_Snapshot.capture()


func _on_efs_script_classes_updated() -> void:
	script_classes_updated.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_diff_on_refocus()


## EFS doesn't emit filesystem_changed for content-only changes to native
## resources (.tres/.tscn) found on the refocus rescan — but our snapshot reads
## real disk mtimes, so a diff here catches them immediately. Changes it finds
## happened while the editor was unfocused, hence EXTERNAL context.
func _diff_on_refocus() -> void:
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	while efs.is_scanning():
		await get_tree().process_frame
	if not is_inside_tree():
		return
	_run_diff(DH_FSM_ChangeSet.EditorContext.EXTERNAL)


func _on_filesystem_changed() -> void:
	if _diff_queued:
		return
	_diff_queued = true
	_run_diff.call_deferred()   # coalesces the bursts filesystem_changed fires in


func _run_diff(context: DH_FSM_ChangeSet.EditorContext = DH_FSM_ChangeSet.EditorContext.UNKNOWN) -> void:
	_diff_queued = false
	if _snapshot == null:
		return   # baseline not captured yet; _capture_baseline is still awaiting
	var new_snapshot: DH_FSM_Snapshot = DH_FSM_Snapshot.capture()
	var changes: DH_FSM_ChangeSet = DH_FSM_SnapshotDiffer.diff(_snapshot, new_snapshot)
	_snapshot = new_snapshot
	changes.editor_context = context
	_emit_changes(changes)


func _emit_changes(changes: DH_FSM_ChangeSet) -> void:
	if changes.is_empty():
		return
	if DEBUG_LOGGING:
		print(changes)
	changes_detected.emit(changes)


# --- FileSystemDock: the only editor_context = EDITOR source -----------------
# Applying the change to the snapshot at signal time doubles as deduplication:
# the follow-up filesystem_changed diff sees no delta for these paths. The dock
# reports a folder operation both per contained file (files_moved/file_removed)
# and as folder_moved/folder_removed; the has()-guards below keep whichever
# arrives first and skip the echo.

func _on_dock_file_removed(file_path: String) -> void:
	if _snapshot == null or not _snapshot.file_mtimes.has(file_path):
		return
	_snapshot.apply_file_removal(file_path)
	var changes: DH_FSM_ChangeSet = DH_FSM_ChangeSet.new()
	changes.editor_context = DH_FSM_ChangeSet.EditorContext.EDITOR
	changes.deleted_file_paths.append(file_path)
	_emit_changes(changes)


func _on_dock_folder_removed(folder_path: String) -> void:
	if _snapshot == null:
		return
	var dir_path: String = DH_FSM_Snapshot.normalize_dir_path(folder_path)
	if not _snapshot.dir_paths.has(dir_path):
		return
	var changes: DH_FSM_ChangeSet = DH_FSM_ChangeSet.new()
	changes.editor_context = DH_FSM_ChangeSet.EditorContext.EDITOR
	changes.deleted_dir_paths.append(dir_path)
	changes.deleted_file_paths = _snapshot.apply_dir_removal(dir_path)
	_emit_changes(changes)


func _on_dock_files_moved(old_file_path: String, new_file_path: String) -> void:
	if _snapshot == null or not _snapshot.file_mtimes.has(old_file_path):
		return
	_snapshot.apply_file_move(old_file_path, new_file_path)
	var changes: DH_FSM_ChangeSet = DH_FSM_ChangeSet.new()
	changes.editor_context = DH_FSM_ChangeSet.EditorContext.EDITOR
	changes.moved_files.append(DH_FSM_Move.new(old_file_path, new_file_path))
	_emit_changes(changes)


## A dock folder move is reported as deleted_dir + created_dir + the per-file
## moves — the same shape a diff-detected folder move has.
func _on_dock_folder_moved(old_folder_path: String, new_folder_path: String) -> void:
	if _snapshot == null:
		return
	var from_dir_path: String = DH_FSM_Snapshot.normalize_dir_path(old_folder_path)
	if not _snapshot.dir_paths.has(from_dir_path):
		return
	var to_dir_path: String = DH_FSM_Snapshot.normalize_dir_path(new_folder_path)
	var changes: DH_FSM_ChangeSet = DH_FSM_ChangeSet.new()
	changes.editor_context = DH_FSM_ChangeSet.EditorContext.EDITOR
	changes.deleted_dir_paths.append(from_dir_path)
	changes.created_dir_paths.append(to_dir_path)
	changes.moved_files = _snapshot.apply_dir_move(from_dir_path, to_dir_path)
	_emit_changes(changes)
