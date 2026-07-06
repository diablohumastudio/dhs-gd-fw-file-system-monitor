# FileSystemMonitor

Granular file-change tracking for Godot editor plugins. Emulates, in GDScript, the
`EditorFileSystem` signals proposed for the engine (`file_created` / `file_modified` /
`file_deleted` / `file_moved`), batched into per-scan `DH_FSM_ChangeSet`s.

## Why

Godot's editor API exposes no granular file signals: `EditorFileSystem.filesystem_changed`
says only that *something* changed, and `FileSystemDock` signals cover only dock-driven
removes/moves. Every plugin that needs to know *what* changed ends up building its own
mtime cache and rescanning. This addon builds that machinery **once** and shares it.

## How it works

- A `DH_FSM_Snapshot` walks the editor's **in-memory** `EditorFileSystemDirectory` tree
  (no `DirAccess` disk walk) storing one mtime and ResourceUID per file.
- On `filesystem_changed` (deferred + coalesced), a fresh snapshot is diffed against the
  previous one: created / modified / deleted, with deletion+creation pairs sharing a UID
  re-paired into **moves**.
- `FileSystemDock` remove/move signals apply directly to the snapshot (deduplicating the
  follow-up scan) and emit immediately with `editor_context = EDITOR`.
- On editor **refocus**, an extra diff catches content-only edits to native resources
  (`.tres`/`.tscn`) that EFS never reports via `filesystem_changed`; those emit with
  `editor_context = EXTERNAL`.
- The baseline snapshot awaits the initial EFS scan, so a partial tree can never fake a
  creation flood.

## API

```gdscript
var monitor: DH_FileSystemMonitorPlugin = DH_FileSystemMonitorPlugin.instance
monitor.changes_detected.connect(_on_files_changed)      # DH_FSM_ChangeSet
monitor.script_classes_updated.connect(_on_classes_updated)

func _on_files_changed(changes: DH_FSM_ChangeSet) -> void:
	# changes.created_file_paths / created_dir_paths     : PackedStringArray
	# changes.modified_file_paths                        : PackedStringArray
	# changes.deleted_file_paths / deleted_dir_paths     : PackedStringArray
	# changes.moved_files                                : Array[DH_FSM_Move] (from_path/to_path)
	# changes.editor_context                             : UNKNOWN | EDITOR | EXTERNAL
	pass
```

One `changes_detected` emission per scan or dock event — a 20-file paste is one ChangeSet,
not 20 signals.

`editor_context` is best-effort: `EDITOR` only for dock-driven removes/moves, `EXTERNAL`
only for refocus-diff findings; everything else is `UNKNOWN` (Godot exposes no editor-side
signal for creates/saves).

## Consumers in this framework

- `visual_resources_editor` — live table refresh.
- `game_database` — debounced auto-regeneration of the baked database.

## Limitations

- Move matching is UID-based; files without UIDs report delete + create instead.
- External changes surface when EFS rescans (typically on editor refocus) — inherent to
  the editor.
- Scan cost is one `FileAccess.get_modified_time()` per project file per scan event.
