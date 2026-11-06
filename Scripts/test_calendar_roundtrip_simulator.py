import unittest
from calendar_roundtrip_simulator import plan, require_ci, verify_owned


class CalendarRoundtripSimulatorTests(unittest.TestCase):
    identifier = "11111111-1111-4111-8111-111111111111"
    runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
    device_type = "com.apple.CoreSimulator.SimDeviceType.iPhone-16"

    def inventory(self, name="iPhone 16", identifier=None):
        return {"devices": {self.runtime: [{"name": name, "udid": identifier or self.identifier,
                "isAvailable": True, "deviceTypeIdentifier": self.device_type}]}}

    def test_plan_uses_verified_runtime_and_device_type_not_a_user_device(self):
        types = {"devicetypes": [{"name": "iPhone 16", "identifier": self.device_type}]}
        self.assertEqual(plan(self.inventory(), types), {"runtime": self.runtime, "deviceType": self.device_type})
        inventory = self.inventory(); del inventory["devices"][self.runtime][0]["deviceTypeIdentifier"]
        self.assertEqual(plan(inventory, types)["deviceType"], self.device_type)

    def test_unknown_ambiguous_and_command_bearing_types_are_rejected(self):
        entry = {"name": "iPhone 16", "identifier": self.device_type}
        for entries in [[], [entry, entry], [{"name": "iPhone 16", "identifier": "untrusted; command"}]]:
            with self.subTest(entries=entries), self.assertRaises(ValueError): plan(self.inventory(), {"devicetypes": entries})

    def test_native_run_requires_macos_github_ci_and_numeric_run_identity(self):
        env = {"GITHUB_ACTIONS": "true", "RUNNER_OS": "macOS", "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1"}
        self.assertEqual(require_ci(env, "darwin"), "Pivot-Calendar-CI-123-1")
        for changed, platform in [({}, "darwin"), (env, "win32"), ({**env, "GITHUB_ACTIONS": "false"}, "darwin"),
                                  ({**env, "GITHUB_RUN_ID": "123; command"}, "darwin")]:
            with self.subTest(changed=changed, platform=platform), self.assertRaises(ValueError): require_ci(changed, platform)

    def test_cleanup_cannot_target_a_template_renamed_or_different_simulator(self):
        owned = {"udid": self.identifier, "name": "Pivot-Calendar-CI-123-1", "runtime": self.runtime}
        verify_owned(self.inventory(name=owned["name"]), owned)
        for inventory in [self.inventory(), {"devices": {}}, self.inventory(name=owned["name"], identifier="22222222-2222-4222-8222-222222222222")]:
            with self.subTest(inventory=inventory), self.assertRaises(ValueError): verify_owned(inventory, owned)


if __name__ == "__main__":
    unittest.main()
