import unittest
from ui_release_shards import discover_tests, expand_plan, load_plan, places_preflight, verify_log, ROOT


class UIReleaseShardTests(unittest.TestCase):
    def test_places_preflight_selects_and_verifies_same_eight_cases(self):
        cases = places_preflight(discover_tests(ROOT))
        self.assertEqual(len(cases), 8)
        self.assertEqual(len(set(cases)), 8)
        self.assertEqual(sum(c.startswith("PremiumCoachInteractionTests/") for c in cases), 3)
        log = "\n".join(f"Test Case '-[PivotUITests.{suite} {method}]' passed (1.0 seconds)."
                        for suite, method in (case.split("/") for case in cases))
        self.assertEqual(verify_log(log, cases), 8)
        with self.assertRaises(ValueError): verify_log("\n".join(log.splitlines()[:-1]), cases)

    def test_places_preflight_rejects_drift_before_native_build(self):
        suites = discover_tests(ROOT)
        suites["SavedPlacesInteractionTests"].append("testNewUnreviewedCase")
        with self.assertRaises(ValueError): places_preflight(suites)
        suites = discover_tests(ROOT)
        suites["PremiumCoachInteractionTests"].remove("testNaturalMissedWorkoutKeepsTomorrowAndAsksWhichSessionBeforeLocalRecovery")
        with self.assertRaises(ValueError): places_preflight(suites)

    def test_places_selection_is_generated_before_build_and_shared_with_verifier(self):
        source = (ROOT / "Scripts/preview-ui.sh").read_text(encoding="utf-8")
        self.assertLess(source.index("--preflight places)"), source.index("if xcodebuild"))
        selection = source.split('elif [ "$PIVOT_UI_ONLY_TESTING" = v8-088-places-regression ]; then', 1)[1].split("elif", 1)[0]
        self.assertIn('done <<< "$PIVOT_PLACES_FLAGS"', selection)
        self.assertIn('--preflight places --verify-log "$PIVOT_UI_LOG"', source)

    def test_repository_coverage_is_complete_and_unique(self):
        plan = load_plan()
        self.assertEqual(sum(map(len, plan.values())), sum(map(len, discover_tests(ROOT).values())))
        self.assertEqual({k: len(v) for k, v in plan.items()}, {"finance": 24, "workout": 22, "profile": 21, "pairing": 20})

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
        self.assertIn("needs: [core, ui, build-iphone]", release)
        self.assertIn('compiled_iphone.py verify', release)
        self.assertLess(release.index('--verify-all-logs'), release.index('tar -xzf'))
        self.assertLess(release.index('compiled_iphone.py verify'), release.index('tar -xzf'))
        build = source.split('  build-iphone:', 1)[1].split('  release:', 1)[0]
        self.assertIn('needs: core', build)
        self.assertNotIn('package-v8-candidate.sh', build)
        self.assertLess(release.index("--verify-all-logs build"), release.index("package-v8-candidate.sh"))
        self.assertNotIn('xcodebuild -project', release)

    def test_ui_execution_is_bounded_without_automatic_retry_or_skips(self):
        source = (ROOT / 'Scripts/preview-ui.sh').read_text(encoding='utf-8')
        self.assertIn('-test-timeouts-enabled YES', source)
        self.assertIn('-maximum-test-execution-time-allowance 600', source)
        self.assertNotIn('-retry-tests-on-failure', source)
        self.assertNotIn('-skip-testing:', source)


if __name__ == "__main__": unittest.main()
