"""Partition the full native suite exactly once; reject missing/skipped results."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SHARDS = {"finance", "workout", "profile", "pairing"}


def discover_tests(root):
    suites = {}
    for path in sorted((root / "UITests").glob("*.swift")):
        source = path.read_text(encoding="utf-8")
        methods = re.findall(r"^\s*func (test\w+)\s*\(", source, re.M)
        if not methods:
            continue
        classes = re.findall(r"^\s*final class (\w+)\s*:\s*XCTestCase\b", source, re.M)
        if len(classes) != 1 or classes[0] in suites or len(set(methods)) != len(methods):
            raise ValueError("ambiguous_test_source")
        suites[classes[0]] = methods
    if not suites:
        raise ValueError("empty_test_suite")
    return suites


def expand_plan(spec, suites):
    if set(spec) != SHARDS:
        raise ValueError("invalid_shard_names")
    expected = {f"{suite}/{method}" for suite, methods in suites.items() for method in methods}
    plan = {}
    for shard, rules in spec.items():
        if not isinstance(rules, list) or not rules:
            raise ValueError("empty_shard")
        cases = []
        for rule in rules:
            if not isinstance(rule, str):
                raise ValueError("invalid_test_rule")
            if rule in suites:
                cases.extend(f"{rule}/{method}" for method in suites[rule])
            elif rule in expected:
                cases.append(rule)
            else:
                raise ValueError("unknown_test_rule")
        plan[shard] = cases
    counted = Counter(case for cases in plan.values() for case in cases)
    if set(counted) != expected or any(count != 1 for count in counted.values()):
        raise ValueError("incomplete_or_duplicate_coverage")
    return plan


def load_plan(root=ROOT):
    spec = json.loads((root / "Scripts/ui-release-shards.json").read_text(encoding="utf-8"))
    return expand_plan(spec, discover_tests(root))


def places_preflight(suites, controls_only=False):
    """One selection for both xcodebuild and verification, never two drifting lists."""
    cases = [f"{suite}/{method}" for suite in ["SavedPlacesInteractionTests", "CalendarCreationInteractionTests"]
             for method in suites[suite]]
    cases += [
        "IncomeCorrectionInteractionTests/testContactDefaultsAndMultipleOriginsPersistAfterRelaunch",
        "PremiumCoachInteractionTests/testNaturalMissedWorkoutKeepsTomorrowAndAsksWhichSessionBeforeLocalRecovery",
        "PremiumCoachInteractionTests/testChatHandsRecoveryToRequestedDayWithoutCalendarWriteOrCloudConsent",
        "PremiumCoachInteractionTests/testRecoveryDateCorrectionRetainsTargetAndExcludedDayAfterRelaunchWithoutCalendarWrite",
    ]
    discovered = {f"{suite}/{method}" for suite, methods in suites.items() for method in methods}
    if len(cases) != 8 or len(set(cases)) != len(cases) or not set(cases) <= discovered:
        raise ValueError("update_explicit_places_preflight_coverage")
    if controls_only:
        cases = [case for case in cases if case.startswith("SavedPlacesInteractionTests/") or
                 case == "PremiumCoachInteractionTests/testRecoveryDateCorrectionRetainsTargetAndExcludedDayAfterRelaunchWithoutCalendarWrite"]
        if len(cases) != 2:
            raise ValueError("update_explicit_places_controls_coverage")
    return cases


def verify_log(text, expected):
    if re.search(r"Test Case[^\n]*\b(?:failed|skipped)\b", text):
        raise ValueError("failed_or_skipped_test")
    passed = [f"{suite}/{method}" for suite, method in re.findall(
        r"Test Case '-\[PivotUITests\.(\w+) (test\w+)\]' passed", text)]
    if Counter(passed) != Counter(expected):
        raise ValueError("missing_duplicate_or_unexpected_test_result")
    return len(passed)


def chart_preflight(suites):
    case = "IncomeCorrectionInteractionTests/testContactBarsKeepOnlyOneExactValueAndCanClearIt"
    if case.split("/")[1] not in suites.get("IncomeCorrectionInteractionTests", []):
        raise ValueError("missing_chart_scroll_regression")
    return [case]


def calendar_controls_preflight(suites):
    cases = ["OnlineCoachInteractionTests/testRoutingPreferencesCanBeRememberedWithoutCreatingAnEvent",
             "CalendarMutationInteractionTests/testTitleUpdateAndUndoLeaveOtherEventAndReceiptsUntouched"]
    if any(case.split("/")[1] not in suites.get(case.split("/")[0], []) for case in cases):
        raise ValueError("missing_calendar_control_regression")
    return cases


def read_log(path):
    if not path.is_file() or path.stat().st_size > 64 * 1024 * 1024:
        raise ValueError("missing_or_oversized_test_log")
    return path.read_text(encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shard", choices=sorted(SHARDS))
    parser.add_argument("--preflight", choices=["places", "places-controls", "chart", "calendar-controls"])
    parser.add_argument("--verify-log", type=Path)
    parser.add_argument("--verify-all-logs", type=Path)
    args = parser.parse_args()
    plan = load_plan()
    if args.preflight:
        if args.shard or args.verify_all_logs:
            parser.error("Choose either preflight or release shard verification")
        suites = discover_tests(ROOT)
        if args.preflight == "chart": cases = chart_preflight(suites)
        elif args.preflight == "calendar-controls": cases = calendar_controls_preflight(suites)
        else: cases = places_preflight(suites, controls_only=args.preflight == "places-controls")
        if args.verify_log:
            print(f"Verified {verify_log(read_log(args.verify_log), cases)} preflight tests, no skips")
        else:
            print("\n".join(f"-only-testing:PivotUITests/{case}" for case in cases))
        return
    if args.verify_all_logs:
        if args.shard or args.verify_log:
            parser.error("Choose one verification mode")
        verified = {name: verify_log(read_log(args.verify_all_logs / f"release-{name}-tests.log"), cases)
                    for name, cases in plan.items()}
        print(json.dumps({"verifiedTests": sum(verified.values()), "shards": verified}, sort_keys=True))
    elif args.verify_log:
        if not args.shard:
            parser.error("--verify-log requires --shard")
        print(f"Verified {verify_log(read_log(args.verify_log), plan[args.shard])} native tests, no skips")
    elif args.shard:
        print("\n".join(f"-only-testing:PivotUITests/{case}" for case in plan[args.shard]))
    else:
        print(json.dumps({name: len(cases) for name, cases in plan.items()}, sort_keys=True))


if __name__ == "__main__":
    main()
