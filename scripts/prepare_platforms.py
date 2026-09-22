from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID_NS = "http://schemas.android.com/apk/res/android"


def main():
    flutter = shutil.which("flutter")
    if not flutter:
        raise SystemExit("Flutter SDK was not found.")

    missing = [
        name for name in ("windows", "android")
        if not (ROOT / name).exists()
    ]

    if missing:
        with tempfile.TemporaryDirectory() as directory:
            template = Path(directory) / "lingua_open"
            subprocess.run(
                [
                    flutter,
                    "create",
                    "--no-pub",
                    "--platforms=" + ",".join(missing),
                    "--project-name=lingua_open",
                    "--org=org.linguaopen",
                    str(template),
                ],
                check=True,
            )

            for name in missing:
                shutil.copytree(template / name, ROOT / name)

    manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    ET.register_namespace("android", ANDROID_NS)
    tree = ET.parse(manifest)
    root = tree.getroot()
    attribute = "{" + ANDROID_NS + "}name"

    has_permission = any(
        item.get(attribute) == "android.permission.INTERNET"
        for item in root.findall("uses-permission")
    )

    if not has_permission:
        permission = ET.Element(
            "uses-permission",
            {attribute: "android.permission.INTERNET"},
        )
        root.insert(0, permission)

    tree.write(manifest, encoding="utf-8", xml_declaration=True)
    print("Windows and Android projects are ready.")


if __name__ == "__main__":
    main()
