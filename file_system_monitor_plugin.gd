@tool
class_name DH_FileSystemMonitorPlugin
extends EditorPlugin

signal script_classes_updated()
signal filesystem_changed()

var _prevent_fs_changed: bool = false

func _enter_tree() -> void:
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if efs:
		if not efs.script_classes_updated.is_connected(_on_script_classes_updated):
			efs.script_classes_updated.connect(_on_script_classes_updated)
		if not efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.connect(_on_filesystem_changed)
	var fsd: FileSystemDock = EditorInterface.get_file_system_dock()
	if fsd:
		if not fsd.file_removed.is_connected(_on_fsd_file_removed):
			fsd.file_removed.connect(_on_fsd_file_removed)

func _on_fsd_file_removed(file: String):
	print(file)


func _exit_tree() -> void:
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if efs:
		if efs.script_classes_updated.is_connected(_on_script_classes_updated):
			efs.script_classes_updated.disconnect(_on_script_classes_updated)
		if efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.disconnect(_on_filesystem_changed)
	var fsd: FileSystemDock = EditorInterface.get_file_system_dock()
	if fsd:
		if fsd.file_removed.is_connected(_on_fsd_file_removed):
			fsd.file_removed.disconnect(_on_fsd_file_removed)

func _on_script_classes_updated() -> void:
	_prevent_fs_changed = true
	script_classes_updated.emit()


func _on_filesystem_changed() -> void:
	if _prevent_fs_changed:
		_prevent_fs_changed = false
		return
	print("fs changed")
	filesystem_changed.emit()
