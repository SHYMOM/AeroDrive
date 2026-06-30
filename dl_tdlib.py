import urllib.request
import json
import zipfile
import os
import shutil
import hashlib

# Pin a specific python-telegram version for reproducible builds
PINNED_VERSION = "0.19.0"
KNOWN_HASH = None  # Set this to a known SHA256 for reproducibility

print(f"Fetching python-telegram v{PINNED_VERSION} package info from PyPI...")
req = urllib.request.urlopen(f"https://pypi.org/pypi/python-telegram/{PINNED_VERSION}/json")
data = json.loads(req.read().decode('utf-8'))
releases = data['urls']

whl_url = None
whl_filename = None
for r in releases:
    if r['filename'].endswith('.whl'):
        whl_url = r['url']
        whl_filename = r['filename']
        break

if not whl_url:
    print(f"Could not find wheel url for version {PINNED_VERSION}!")
    exit(1)

print(f"Downloading {whl_filename}...")
urllib.request.urlretrieve(whl_url, whl_filename)

if KNOWN_HASH:
    sha256 = hashlib.sha256()
    with open(whl_filename, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            sha256.update(chunk)
    if sha256.hexdigest() != KNOWN_HASH:
        print(f"Hash mismatch! Expected {KNOWN_HASH}, got {sha256.hexdigest()}")
        os.remove(whl_filename)
        exit(1)
    print("Hash verified successfully.")

print(f"Extracting tdjson.dll...")
with zipfile.ZipFile(whl_filename, 'r') as z:
    for item in z.namelist():
        if item.endswith('tdjson.dll'):
            print(f"Found {item}!")
            target_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tdlib')
            os.makedirs(target_dir, exist_ok=True)
            target_path = os.path.join(target_dir, 'tdjson.dll')
            with z.open(item) as source, open(target_path, "wb") as target:
                shutil.copyfileobj(source, target)
            print(f"Successfully copied to {target_path}")
            break

os.remove(whl_filename)
print("Cleanup complete.")
