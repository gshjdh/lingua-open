"""Generate missing native hosts without changing application sources."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID_NS = "http://schemas.android.com/apk/res/android"


def prepare():
    flutter = shutil.which("flutter")
    if not flutter:
        raise SystemExit("Flutter SDK is required on PATH.")
    missing = [name for name in ("windows", "android") if not (ROOT / name).exists()]
    if missing:
        with tempfile.TemporaryDirectory() as directory:
            template = Path(directory) / "lingua_open"
            subprocess.run([
                flutter, "create", "--no-pub", "--platforms=" + ",".join(missing),
                "--project-name=lingua_open", "--org=org.linguaopen", str(template)
            ], check=True)
            for name in missing:
                shutil.copytree(template / name, ROOT / name)
    manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    ET.register_namespace("android", ANDROID_NS)
    tree = ET.parse(manifest)
    root = tree.getroot()
    name_attribute = "{" + ANDROID_NS + "}name"
    if not any(p.get(name_attribute) == "android.permission.INTERNET"
               for p in root.findall("uses-permission")):
        root.insert(0, ET.Element("uses-permission", {
            name_attribute: "android.permission.INTERNET"
        }))
    tree.write(manifest, encoding="utf-8", xml_declaration=True)
    print("Native hosts ready; Android internet permission enabled.")


if __name__ == "__main__":
    prepare()
