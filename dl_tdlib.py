import urllib.request
import json
import zipfile
import os
import shutil

print("Fetching python-telegram package info from PyPI...")
req = urllib.request.urlopen("https://pypi.org/pypi/python-telegram/json")
data = json.loads(req.read().decode('utf-8'))
releases = data['urls']

whl_url = None
for r in releases:
    if r['filename'].endswith('.whl'):
        whl_url = r['url']
        whl_filename = r['filename']
        break

if not whl_url:
    print("Could not find wheel url!")
    exit(1)

print(f"Downloading {whl_filename}...")
urllib.request.urlretrieve(whl_url, whl_filename)

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
