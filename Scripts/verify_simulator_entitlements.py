"""Inspect actual simulator Mach-O entitlements, not the device code-signature slot."""
import plistlib
import struct
import sys
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def thin_entitlements(raw):
    require(len(raw) >= 32 and raw[:4] == b"\xcf\xfa\xed\xfe", "Expected 64-bit simulator Mach-O")
    count, size = struct.unpack_from("<II", raw, 16)
    require(0 < count <= 4096 and 32 + size <= len(raw), "Invalid load commands")
    position = 32
    found = []
    for _ in range(count):
        require(position + 8 <= 32 + size, "Truncated load command")
        command, length = struct.unpack_from("<II", raw, position)
        require(length >= 8 and position + length <= 32 + size, "Invalid load command length")
        if command == 0x19:  # LC_SEGMENT_64
            require(length >= 72, "Truncated segment")
            sections = struct.unpack_from("<I", raw, position + 64)[0]
            require(sections <= 128 and 72 + sections * 80 <= length, "Invalid section count")
            for index in range(sections):
                start = position + 72 + index * 80
                name = raw[start:start + 16].rstrip(b"\0")
                segment = raw[start + 16:start + 32].rstrip(b"\0")
                if (segment, name) != (b"__TEXT", b"__entitlements"):
                    continue
                length_bytes = struct.unpack_from("<Q", raw, start + 40)[0]
                offset = struct.unpack_from("<I", raw, start + 48)[0]
                require(0 < length_bytes <= 65536 and offset + length_bytes <= len(raw), "Invalid entitlement section")
                found.append(plistlib.loads(raw[offset:offset + length_bytes].rstrip(b"\0")))
        position += length
    require(len(found) == 1, "Expected one embedded simulator entitlement section")
    return found[0]


def inspect(raw, expected):
    require(0 < len(raw) <= 256 * 1024 * 1024, "Invalid executable size")
    slices = [raw]
    if raw[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        require(len(raw) >= 8, "Truncated universal header")
        count = struct.unpack_from(">I", raw, 4)[0]
        stride = 32 if raw[:4] == b"\xca\xfe\xba\xbf" else 20
        require(0 < count <= 8 and 8 + count * stride <= len(raw), "Invalid architecture count")
        slices = []
        for index in range(count):
            start = 8 + index * stride
            offset, size = struct.unpack_from(">QQ" if stride == 32 else ">II", raw, start + 8)
            require(offset >= 8 + count * stride and size > 0 and offset + size <= len(raw), "Invalid architecture bounds")
            slices.append(raw[offset:offset + size])
    result = None
    for binary in slices:
        entitlements = thin_entitlements(binary)
        require(entitlements.get("application-identifier") == expected, "Simulator QA app identity missing")
        require(entitlements.get("keychain-access-groups") == [expected], "Simulator QA private Keychain group missing")
        require(entitlements.get("get-task-allow") is True, "Simulator debugging entitlement missing")
        require(entitlements.get("com.apple.developer.healthkit") is True, "Simulator HealthKit entitlement missing")
        require(entitlements.get("com.apple.developer.healthkit.background-delivery") is True, "Simulator HealthKit background entitlement missing")
        require(result is None or result == entitlements, "Simulator architecture entitlements differ")
        result = entitlements
    return result


if __name__ == "__main__":
    app = Path(sys.argv[1])
    info = plistlib.loads((app / "Info.plist").read_bytes())
    require(info["CFBundleIdentifier"] == "app.pivot.personal", "Unexpected simulator app")
    executable = info["CFBundleExecutable"]
    require(executable == "Pivot", "Unexpected executable")
    value = inspect((app / executable).read_bytes(), "PIVOTSIMQA." + info["CFBundleIdentifier"])
    Path(sys.argv[2]).write_bytes(plistlib.dumps(value))
    print("Simulator QA identity verified in every Mach-O slice (synthetic; not iPhone signing).")
