"""Builds every level JSON plus the campaign index.

Run:  python tools/levels/build_all.py
"""

import importlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from builder import LEVELS_OUT  # noqa: E402

WORLD_MODULES = ["world1", "world2", "world3", "world4", "world5"]


def main():
    os.makedirs(LEVELS_OUT, exist_ok=True)
    # Clear stale level files so a renamed or removed level cannot linger in
    # the bundle and get picked up by the index.
    for name in os.listdir(LEVELS_OUT):
        if name.endswith(".json"):
            os.remove(os.path.join(LEVELS_OUT, name))

    by_world = {}
    total = 0
    for mod_name in WORLD_MODULES:
        try:
            mod = importlib.import_module(mod_name)
        except ModuleNotFoundError:
            print(f"  (skipping {mod_name}: not written yet)")
            continue
        importlib.reload(mod)
        for L in mod.build_all():
            L.save()
            w = str(L.data["world"])
            by_world.setdefault(w, []).append(L.data["id"])
            total += 1
        print(f"  {mod_name}: {len(by_world.get(mod_name[-1], []))} levels")

    index = {"worlds": by_world, "count": total}
    with open(os.path.join(LEVELS_OUT, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, separators=(",", ":"))

    print(f"\n{total} levels written to {LEVELS_OUT}")
    for w in sorted(by_world):
        print(f"  world {w}: {len(by_world[w])}")


if __name__ == "__main__":
    main()
