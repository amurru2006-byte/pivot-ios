import unittest
from select_simulator import select


def phone(name="iPhone 16", identifier="11111111-1111-4111-8111-111111111111", available=True):
    return dict(name=name, udid=identifier, isAvailable=available)


def inventory(entries):
    return dict(devices={"com.apple.CoreSimulator.SimRuntime." + key: value for key, value in entries.items()})


class SimulatorSelectionTests(unittest.TestCase):
    def test_newest_runtime_wins_even_if_old_iphone_16_is_first(self):
        result = select(inventory({"iOS-18-5": [phone()], "iOS-26-0": [phone()], "iOS-26-2": [phone()]}))
        self.assertEqual(result["version"], (26, 2, 0))

    def test_newer_runtime_beats_preferred_phone_model(self):
        result = select(inventory({"iOS-26-0": [phone()], "iOS-26-2": [phone("iPhone 17")]}))
        self.assertEqual(result["name"], "iPhone 17")

    def test_iphone_16_is_preferred_within_same_runtime(self):
        result = select(inventory({"iOS-26-2": [phone("iPhone 17"), phone()]}))
        self.assertEqual(result["name"], "iPhone 16")

    def test_unavailable_wrong_platform_ipad_and_invalid_identifier_are_ignored(self):
        result = select(inventory({"iOS-27-0": [phone(available=False), phone("iPad"), phone(identifier="not-a-uuid")],
                                   "watchOS-27-0": [phone()], "iOS-26-2": [phone()]}))
        self.assertEqual(result["version"], (26, 2, 0))

    def test_old_only_inventory_fails_instead_of_skipping_alarm_probe(self):
        with self.assertRaisesRegex(ValueError, "no_available_iphone"):
            select(inventory({"iOS-18-6": [phone()]}))

    def test_malformed_inventory_is_rejected(self):
        for data in [None, [], {}, dict(devices=[])]:
            with self.assertRaises(ValueError):
                select(data)


if __name__ == "__main__":
    unittest.main()
