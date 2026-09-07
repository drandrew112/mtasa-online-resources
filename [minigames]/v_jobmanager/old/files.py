import os

INPUT_DIR = os.getcwd()     # gyökér mappa
OUTPUT_FILE = "files.txt"

VALID_EXTENSIONS = (".lua", ".xml")

print("CWD:", os.getcwd())

with open(OUTPUT_FILE, "w", encoding="utf-8") as out:
    for root, _, files in os.walk(INPUT_DIR):
        for file in files:
            if file.endswith(VALID_EXTENSIONS):
                file_path = os.path.join(root, file)
                relative_path = os.path.relpath(file_path, INPUT_DIR)

                print(relative_path)
                out.write(f"{relative_path}\n")

                try:
                    with open(file_path, "r", encoding="utf-8") as f:
                        out.write(f.read())
                except UnicodeDecodeError:
                    out.write("[HIBA: fájl nem UTF-8 kódolású]")

                out.write("\n\n###\n\n")

print("Kész ✔ Almappákkal együtt összegyűjtve.")
