"""Run the synthetic Calendar host only in a newly owned GitHub CI simulator."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import uuid
from select_simulator import select


def require_ci(env, platform):
    if platform != "darwin" or env.get("GITHUB_ACTIONS") != "true" or env.get("RUNNER_OS") != "macOS":
        raise ValueError("calendar_roundtrip_is_github_macos_ci_only")
    run, attempt = env.get("GITHUB_RUN_ID", ""), env.get("GITHUB_RUN_ATTEMPT", "")
    if not re.fullmatch(r"[0-9]+", run) or not re.fullmatch(r"[0-9]+", attempt):
        raise ValueError("invalid_ci_identity")
    return f"Pivot-Calendar-CI-{run}-{attempt}"


def plan(inventory, types):
    selected = select(inventory)
    device = next(item for item in inventory["devices"][selected["runtime"]] if item.get("udid") == selected["udid"])
    known = types.get("devicetypes", []) if isinstance(types, dict) else []
    identifier = device.get("deviceTypeIdentifier")
    matches = [item for item in known if isinstance(item, dict) and
               (item.get("identifier") == identifier if identifier else item.get("name") == selected["name"])]
    if len(matches) != 1 or not re.fullmatch(r"com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-[A-Za-z0-9-]+", matches[0].get("identifier", "")):
        raise ValueError("cannot_verify_exact_iphone_device_type")
    return dict(runtime=selected["runtime"], deviceType=matches[0]["identifier"])


def verify_owned(inventory, owned):
    identifier, name, runtime = owned.get("udid", ""), owned.get("name", ""), owned.get("runtime", "")
    if str(uuid.UUID(identifier)).lower() != identifier.lower() or not re.fullmatch(r"Pivot-Calendar-CI-[0-9]+-[0-9]+", name):
        raise ValueError("invalid_owned_simulator_identity")
    matches = [(key, device) for key, devices in inventory.get("devices", {}).items() for device in devices
               if isinstance(device, dict) and device.get("udid") == identifier]
    if len(matches) != 1 or matches[0][0] != runtime or matches[0][1].get("name") != name:
        raise ValueError("simulator_ownership_changed_no_cleanup_performed")


def command(args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def main():
    name = require_ci(os.environ, sys.platform)  # before any native operation
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    build = root / "build"
    build.mkdir(exist_ok=True)
    logfile = build / "calendar-roundtrip.log"
    proof_file = build / "calendar-roundtrip-owned.json"
    if logfile.exists() or proof_file.exists():
        raise ValueError("refuse_to_overwrite_roundtrip_evidence")
    inventory = json.loads(command(["xcrun", "simctl", "list", "devices", "available", "-j"]))
    types = json.loads(command(["xcrun", "simctl", "list", "devicetypes", "-j"]))
    spec = plan(inventory, types)
    identifier = command(["xcrun", "simctl", "create", name, spec["deviceType"], spec["runtime"]]).strip()
    if str(uuid.UUID(identifier)).lower() != identifier.lower():
        raise ValueError("created_simulator_did_not_return_a_uuid")
    owned = dict(udid=identifier, name=name, **spec, created=True, deleted=False)
    with proof_file.open("x", encoding="utf-8") as out:
        json.dump(owned, out, indent=2)
    try:
        verify_owned(json.loads(command(["xcrun", "simctl", "list", "devices", "-j"])), owned)
        command(["xcrun", "simctl", "boot", identifier])
        command(["xcrun", "simctl", "bootstatus", identifier, "-b"])
        args = ["xcodebuild", "-project", "Pivot.xcodeproj", "-scheme", "PivotCalendarRoundtrip", "-configuration", "Debug",
                "-destination", "platform=iOS Simulator,id=" + identifier, "-parallel-testing-enabled", "NO",
                "-derivedDataPath", "build/CalendarRoundtripDerivedData", "-resultBundlePath", "build/CalendarRoundtrip.xcresult",
                "CODE_SIGNING_ALLOWED=YES", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=-", "test"]
        with logfile.open("x", encoding="utf-8") as log:
            process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
            for line in process.stdout:
                log.write(line); print(line, end="", flush=True)
            code = process.wait()
            if code:
                raise subprocess.CalledProcessError(code, args)
    finally:
        # Never erase or shut down a template, pre-existing, missing or renamed
        # simulator. Cleanup is confined to the exact UUID created above.
        verify_owned(json.loads(command(["xcrun", "simctl", "list", "devices", "-j"])), owned)
        subprocess.run(["xcrun", "simctl", "shutdown", identifier], check=False, capture_output=True)
        command(["xcrun", "simctl", "delete", identifier])
        remaining = json.loads(command(["xcrun", "simctl", "list", "devices", "-j"]))
        if any(device.get("udid") == identifier for devices in remaining.get("devices", {}).values() for device in devices):
            raise ValueError("owned_simulator_still_exists_after_delete")
        owned["deleted"] = True
        proof_file.write_text(json.dumps(owned, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
