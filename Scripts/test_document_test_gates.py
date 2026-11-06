import unittest
from document_test_gates import expected, verify, ROOT


class DocumentTestGateTests(unittest.TestCase):
    def log(self, cases, native=False):
        return "\n".join([f"Test Case 'Synthetic.{suite}.{method}' passed (0.0 seconds)." for suite, method in cases]
                         + (["** TEST SUCCEEDED **"] if native else []))

    def test_source_plan_includes_all_current_cases_and_two_real_roundtrip_tests(self):
        self.assertEqual(len(expected("core")), 72)
        self.assertEqual(len(expected("native")), 28)
        self.assertEqual(len(expected("roundtrip")), 2)
        with self.assertRaises(ValueError): expected("unknown")

    def test_missing_duplicate_and_renamed_results_cannot_complete_a_gate(self):
        cases = [("FixtureTests", "testOne"), ("FixtureTests", "testTwo")]
        good = self.log(cases)
        self.assertEqual(verify(good, cases), 2)
        for changed in [good.splitlines()[0], good + "\n" + good.splitlines()[0], good.replace("testOne", "testOneRenamed")]:
            with self.subTest(changed=changed), self.assertRaises(ValueError): verify(changed, cases)

    def test_failure_or_skip_is_rejected_even_if_all_expected_cases_also_passed(self):
        cases = [("FixtureTests", "testOne")]
        for state in ["failed", "skipped"]:
            log = self.log(cases) + f"\nTest Case 'Unrelated.testOther' {state} (0.0 seconds)."
            with self.subTest(state=state), self.assertRaises(ValueError): verify(log, cases)

    def test_native_gate_requires_success_marker_and_whole_test_name(self):
        cases = [("FixtureTests", "testOne")]
        self.assertEqual(verify(self.log(cases, native=True), cases, native=True), 1)
        for changed in [self.log(cases), self.log(cases, native=True).replace("FixtureTests", "FixtureTestsOther")]:
            with self.subTest(changed=changed), self.assertRaises(ValueError): verify(changed, cases, native=True)

    def test_document_release_requires_same_run_native_roundtrip_and_full_ui_before_packaging(self):
        source = (ROOT / ".github/workflows/documents-release.yml").read_text(encoding="utf-8")
        self.assertIn("branches: ['codex/pivot-documents-release']", source)
        self.assertIn("contents: read", source)
        self.assertIn("shard: [finance, workout, profile, pairing]", source)
        self.assertNotIn("continue-on-error:", source)
        release = source.split("  release:", 1)[1].split("  document-native:", 1)[0]
        self.assertIn("needs: [core, ui, build-iphone, document-native, eventkit-roundtrip]", release)
        for required in ["document_test_gates.py core", "document_test_gates.py native", "document_test_gates.py roundtrip",
                         "--verify-all-logs", "compiled_iphone.py verify"]:
            self.assertLess(release.index(required), release.index("package-v8-candidate.sh"))
        self.assertNotIn("run-id:", release)
        self.assertNotIn("gh release", source)
        self.assertNotIn("--clobber", source)


if __name__ == "__main__": unittest.main()
