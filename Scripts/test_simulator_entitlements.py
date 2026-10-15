import plistlib
import struct
import unittest

from verify_simulator_entitlements import inspect


EXPECTED = "PIVOTSIMQA.app.pivot.personal"


def fixture(group=EXPECTED):
    payload = plistlib.dumps({"application-identifier": EXPECTED, "keychain-access-groups": [group],
                             "get-task-allow": True, "com.apple.developer.healthkit": True,
                             "com.apple.developer.healthkit.background-delivery": True})
    header = struct.pack("<8I", 0xFEEDFACF, 0x01000007, 3, 2, 1, 152, 0, 0)
    segment = struct.pack("<II16s4Q4I", 0x19, 152, b"__TEXT", 0, 0, 0, 0, 7, 5, 1, 0)
    section = struct.pack("<16s16sQQ8I", b"__entitlements", b"__TEXT", 0, len(payload), 184, 0, 0, 0, 0, 0, 0, 0)
    return header + segment + section + payload


def universal(first, second):
    offset = 48
    return (struct.pack(">II", 0xCAFEBABE, 2)
            + struct.pack(">5I", 0x01000007, 3, offset, len(first), 0)
            + struct.pack(">5I", 0x0100000C, 0, offset + len(first), len(second), 0)
            + first + second)


class SimulatorEntitlementsTests(unittest.TestCase):
    def test_reads_built_section_not_code_signature(self):
        self.assertEqual(inspect(fixture(), EXPECTED)["keychain-access-groups"], [EXPECTED])

    def test_checks_every_universal_slice(self):
        self.assertEqual(inspect(universal(fixture(), fixture()), EXPECTED)["application-identifier"], EXPECTED)
        with self.assertRaises(ValueError):
            inspect(universal(fixture(), fixture("unapproved")), EXPECTED)

    def test_missing_or_truncated_section_is_rejected(self):
        for raw in [b"", b"invalid", fixture()[:32], fixture()[:-5]]:
            with self.subTest(size=len(raw)), self.assertRaises((ValueError, plistlib.InvalidFileException)):
                inspect(raw, EXPECTED)

    def test_wrong_group_or_identity_is_rejected(self):
        with self.assertRaises(ValueError):
            inspect(fixture("wrong"), EXPECTED)
        with self.assertRaises(ValueError):
            inspect(fixture(), "wrong")

    def test_universal_bounds_are_checked_before_reading(self):
        raw = bytearray(universal(fixture(), fixture()))
        struct.pack_into(">I", raw, 16, 0xFFFFFFFF)
        with self.assertRaises(ValueError):
            inspect(bytes(raw), EXPECTED)


if __name__ == "__main__":
    unittest.main()
