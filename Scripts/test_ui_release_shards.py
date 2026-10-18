import unittest
from ui_release_shards import discover_tests, expand_plan, load_plan, verify_log, ROOT


class UIReleaseShardTests(unittest.TestCase):
    def test_repository_coverage_is_complete_and_unique(self):
        plan = load_plan()
        self.assertEqual(sum(map(len, plan.values())), sum(map(len, discover_tests(ROOT).values())))
        self.assertEqual({k: len(v) for k, v in plan.items()}, {"finance": 25, "workout": 12, "profile": 17, "pairing": 5})

    def fixture(self):
        suites = {"ExampleTests": ["testA", "testB", "testC", "testD"]}
        spec = {name: [f"ExampleTests/test{letter}"] for name, letter in zip(["finance", "workout", "profile", "pairing"], "ABCD")}
        return spec, suites

    def test_missing_method_is_rejected(self):
        spec, suites = self.fixture(); suites["ExampleTests"].append("testNew")
        with self.assertRaises(ValueError): expand_plan(spec, suites)

    def test_duplicate_method_is_rejected(self):
        spec, suites = self.fixture(); spec["finance"].append("ExampleTests/testB")
        with self.assertRaises(ValueError): expand_plan(spec, suites)

    def test_unknown_method_is_rejected(self):
        spec, suites = self.fixture(); spec["finance"] = ["MissingTests"]
        with self.assertRaises(ValueError): expand_plan(spec, suites)

    def test_unexpected_shard_is_rejected(self):
        spec, suites = self.fixture(); spec["other"] = spec.pop("finance")
        with self.assertRaises(ValueError): expand_plan(spec, suites)

    def test_exact_native_results_are_required(self):
        text = "Test Case '-[PivotUITests.ExampleTests testA]' passed (1.0 seconds).\n"
        self.assertEqual(verify_log(text, ["ExampleTests/testA"]), 1)
        for changed in ["", text + text, text.replace("testA", "testB")]:
            with self.subTest(changed=changed), self.assertRaises(ValueError): verify_log(changed, ["ExampleTests/testA"])

    def test_failed_or_skipped_results_are_rejected(self):
        for status in ["failed", "skipped"]:
            text = f"Test Case '-[PivotUITests.ExampleTests testA]' {status} (1.0 seconds).\n"
            with self.subTest(status=status), self.assertRaises(ValueError): verify_log(text, ["ExampleTests/testA"])

    def test_release_workflow_requires_every_shard_and_verifies_results(self):
        source = (ROOT / ".github/workflows/v8-calendar.yml").read_text(encoding="utf-8")
        self.assertIn("shard: [finance, workout, profile, pairing]", source)
        self.assertIn("fail-fast: false", source)
        self.assertNotRegex(source, r"(?m)^\s*continue-on-error:")
        release = source.split("  release:", 1)[1]
        self.assertIn("needs: [core, ui]", release)
        self.assertLess(release.index("--verify-all-logs build"), release.index("xcodebuild -project"))


if __name__ == "__main__": unittest.main()
