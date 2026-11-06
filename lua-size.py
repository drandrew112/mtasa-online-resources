import os
import xml.etree.ElementTree as ET
from collections import defaultdict

ROOT_DIR = "."

stats = {
    "client": {"size": 0, "count": 0},
    "server": {"size": 0, "count": 0},
    "shared": {"size": 0, "count": 0},
}

resources = defaultdict(lambda: {"client": 0, "server": 0, "shared": 0})

errors = []
missing = []
resource_count = 0

def format_size(size):
    return f"{size / 1024 / 1024:.2f} MB"

print("MTA:SA Lua Analyzer indul...\n", flush=True)

for root, dirs, files in os.walk(ROOT_DIR):
    if "meta.xml" not in files:
        continue

    meta_path = os.path.join(root, "meta.xml")
    resource_name = os.path.relpath(root, ROOT_DIR)

    try:
        tree = ET.parse(meta_path)
        meta = tree.getroot()
        resource_count += 1

        for script in meta.findall(".//script"):
            src = script.get("src")
            if not src or not src.lower().endswith(".lua"):
                continue

            script_type = script.get("type", "server").lower()

            if script_type not in stats:
                continue

            # Windows és MTA útvonalak kezelése
            src = src.replace("\\", "/")
            file_path = os.path.normpath(
                os.path.join(root, src.replace("/", os.sep))
            )

            if not os.path.isfile(file_path):
                missing.append(f"{resource_name}: {src}")
                continue

            size = os.path.getsize(file_path)

            stats[script_type]["size"] += size
            stats[script_type]["count"] += 1
            resources[resource_name][script_type] += size

    except Exception as e:
        errors.append(f"{meta_path}: {e}")

# EREDMÉNYEK
print("\n" + "=" * 60)
print("             MTA:SA LUA ANALYZER")
print("=" * 60)

print(f"\nFeldolgozott resource-ok: {resource_count}")

for category in ("client", "server", "shared"):
    data = stats[category]

    print(f"\n{category.upper()}")
    print(f"Fájlok: {data['count']}")
    print(f"Méret:  {format_size(data['size'])}")

total_size = sum(x["size"] for x in stats.values())
total_count = sum(x["count"] for x in stats.values())

print("\n" + "=" * 60)
print("ÖSSZESÍTÉS")
print("=" * 60)
print(f"Lua fájlok összesen: {total_count}")
print(f"Teljes méret: {format_size(total_size)}")

print("\nLEGNAGYOBB RESOURCE-OK:")
for name, data in sorted(
    resources.items(),
    key=lambda x: sum(x[1].values()),
    reverse=True
)[:20]:
    total = sum(data.values())
    print(f"{name:<40} {format_size(total)}")

print("\n" + "=" * 60)
print(f"Hiányzó fájlok: {len(missing)}")
print(f"Hibás meta.xml: {len(errors)}")
print("=" * 60)

for item in errors:
    print("XML HIBA:", item)

for item in missing[:30]:
    print("HIÁNYZIK:", item)

input("\nNyomj ENTER-t a kilépéshez...")