"""Select a real available modern iPhone, not the first matching device name."""
import argparse
import json
from pathlib import Path
import re
import uuid


def select(data, minimum_major=26):
    if not isinstance(data, dict) or not isinstance(data.get("devices"), dict):
        raise ValueError("invalid_device_inventory")
    candidates = []
    for runtime, devices in data["devices"].items():
        match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+)-(\d+)(?:-(\d+))?", runtime)
        if not match or not isinstance(devices, list):
            continue
        version = tuple(int(value or 0) for value in match.groups())
        if version[0] < minimum_major:
            continue
        for device in devices:
            if not isinstance(device, dict) or device.get("isAvailable") is not True:
                continue
            name, udid = device.get("name"), device.get("udid")
            if not isinstance(name, str) or not name.startswith("iPhone") or not isinstance(udid, str):
                continue
            try:
                parsed = uuid.UUID(udid)
            except ValueError:
                continue
            if str(parsed).lower() != udid.lower():
                continue
            candidates.append(dict(runtime=runtime, version=version, name=name, udid=udid))
    if not candidates:
        raise ValueError("no_available_iphone_ios_26_or_later")
    newest = max(item["version"] for item in candidates)
    return min((item for item in candidates if item["version"] == newest),
               key=lambda item: (item["name"] != "iPhone 16", item["name"], item["udid"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("inventory")
    parser.add_argument("--metadata-out", required=True)
    args = parser.parse_args()
    selected = select(json.loads(Path(args.inventory).read_text()))
    Path(args.metadata_out).write_text(json.dumps(selected, indent=2) + "\n")
    print(selected["udid"])
