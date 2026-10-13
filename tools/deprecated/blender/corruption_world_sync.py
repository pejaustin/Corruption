"""Corruption: export the world at all three sizes whenever world_landscape.blend is saved.

Install (once): Blender > Edit > Preferences > Add-ons > the down arrow (top right) > Install from Disk... > pick this
file, then tick "Corruption: world sync" (or copy it into Blender's scripts/addons folder).

What it does: after you save `art/world/source/world_landscape.blend` it runs, in background Blender processes on the
file you just saved (your open session is not touched, nothing is saved back), tools/blender/export_landscape.py for
400m, 2km and 6km. That writes art/world/export/world_landscape_<size>.glb; Godot re-imports them when its window gets
focus. The repo is found from the file's own path (<repo>/art/world/source/world_landscape.blend).

It does NOT run the Godot steps (rebuilding the 400 m / 6 km scenes, navmeshes, map pictures): after a change to the
ground or the markers run tools/sync_world_sizes.sh --no-export, see art/world/README.md, "Sizes".
"""

bl_info = {
    "name": "Corruption: world sync",
    "author": "Claude (for Austin)",
    "version": (1, 0, 0),
    "blender": (4, 0, 0),
    "location": "Saving world_landscape.blend",
    "description": "On saving world_landscape.blend, exports the 400 m, 2 km and 6 km glb files for Godot",
    "category": "Import-Export",
}

import os
import subprocess
import threading

import bpy
from bpy.app.handlers import persistent

SIZES = ("400m", "2km", "6km")
MAP_FILE = "world_landscape.blend"
EXPORT_SCRIPT = os.path.join("tools", "blender", "export_landscape.py")

_busy = False
_message = ""


def _repo_root(blend_path):
    """<repo>/art/world/source/world_landscape.blend -> <repo>, or None when the file is not in that place."""
    source_dir = os.path.dirname(os.path.abspath(blend_path))
    root = os.path.abspath(os.path.join(source_dir, "..", "..", ".."))
    if os.path.isfile(os.path.join(root, EXPORT_SCRIPT)):
        return root
    return None


def _export_all(blend_path, root):
    """Runs on a thread: one background Blender per size, one after another."""
    global _busy, _message
    failed = []
    for size in SIZES:
        cmd = [bpy.app.binary_path, "-b", blend_path, "--python", os.path.join(root, EXPORT_SCRIPT), "--", root, size]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
            out = result.stdout + result.stderr
            if result.returncode != 0 or "GEOMETRY_AND_NAMES_UNCHANGED True" not in out:
                failed.append(size)
                print("[corruption_world_sync] %s failed:\n%s" % (size, out[-2000:]))
        except Exception as error:  # noqa: BLE001 (any failure is shown to the user, not raised into Blender)
            failed.append(size)
            print("[corruption_world_sync] %s: %s" % (size, error))
    _message = "Corruption: export failed for %s (see the console)" % ", ".join(failed) if failed else \
        "Corruption: exported 400m, 2km, 6km. Next: tools/sync_world_sizes.sh --no-export (or just focus Godot to re-import)"
    _busy = False
    bpy.app.timers.register(_show_message, first_interval=0.1)


def _show_message():
    """Back on Blender's main thread: show the result in the status bar for a while."""
    try:
        bpy.context.workspace.status_text_set(_message)
        bpy.app.timers.register(_clear_message, first_interval=20.0)
    except Exception:  # noqa: BLE001 (no window, e.g. background mode)
        print("[corruption_world_sync] " + _message)
    return None


def _clear_message():
    try:
        bpy.context.workspace.status_text_set(None)
    except Exception:  # noqa: BLE001
        pass
    return None


@persistent
def _on_save(*_args):
    global _busy, _message
    path = bpy.data.filepath
    if not path or os.path.basename(path) != MAP_FILE or _busy:
        return
    root = _repo_root(path)
    if root is None:
        print("[corruption_world_sync] %s is not inside a Corruption checkout (no %s); nothing exported" % (path, EXPORT_SCRIPT))
        return
    _busy = True
    _message = ""
    try:
        bpy.context.workspace.status_text_set("Corruption: exporting 400m, 2km and 6km...")
    except Exception:  # noqa: BLE001
        pass
    threading.Thread(target=_export_all, args=(path, root), daemon=True).start()


def register():
    if _on_save not in bpy.app.handlers.save_post:
        bpy.app.handlers.save_post.append(_on_save)


def unregister():
    if _on_save in bpy.app.handlers.save_post:
        bpy.app.handlers.save_post.remove(_on_save)


if __name__ == "__main__":
    register()
