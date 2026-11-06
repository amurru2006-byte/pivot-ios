"""Require every named document test exactly once; no failed/skipped results."""
import argparse
import json
from pathlib import Path
import re
import uuid

ROOT = Path(__file__).resolve().parents[1]
CORE = {"CoachDocumentSourceTests": 8, "CoachDocumentLibraryTests": 8, "CoachDocumentEventProposalTests": 8,
        "CalendarCreationAllDayTests": 8, "CoachDocumentImportTests": 8, "CoachDocumentPageSelectionTests": 6,
        "CoachDocumentLocalProposalsTests": 8, "CoachDocumentReviewTests": 8, "CoachDocumentExchangeTests": 8}
NATIVE = {"CoachDocumentReaderTests": 8, "CalendarCreationNativeTests": 8, "CoachDocumentStorageTests": 8,
          "CoachDocumentReplyFileTests": 4}
PRIVACY = ["testLocalAllDayDraftCannotBeSentAsAnAppointmentAtMidnight",
           "testDocumentBackedDraftAndHistoryStayLocalEvenIfMessagesWerePreviouslyEligible"]
AI = {"CoachPlanningAlternativesTests": 32, "CoachAgendaSignalsTests": 21,
      "CoachPlanningLogisticsTests": 17, "CoachPlanningDurationChoiceTests": 8}


def expected(kind, root=ROOT):
    groups = [("Tests/PivotCoreTests", CORE)] if kind == "core" else [("IOSTests", NATIVE)] if kind == "native" else [
        ("CalendarRoundtripUITests", {"EventKitRoundtripInteractionTests": 2})]
    if kind not in {"core", "native", "roundtrip"}:
        raise ValueError("unknown_document_gate")
    result = []
    for folder, suites in groups:
        for suite, count in suites.items():
            source = (root / folder / (suite + ".swift")).read_text(encoding="utf-8")
            methods = re.findall(r"^\s*func (test\w+)\s*\(", source, re.M)
            if len(methods) != len(set(methods)) or len(methods) != count:
                raise ValueError("document_test_source_drift:" + suite)
            result.extend((suite, method) for method in methods)
    if kind == "core":
        source = (root / "Tests/PivotCoreTests/CoachPremiumContextTests.swift").read_text(encoding="utf-8")
        for method in PRIVACY:
            if len(re.findall(r"func " + re.escape(method) + r"\(", source)) != 1:
                raise ValueError("privacy_test_source_drift")
        result.extend(("CoachPremiumContextTests", method) for method in PRIVACY)
    if len(result) != {"core": 72, "native": 28, "roundtrip": 2}[kind] or len(set(result)) != len(result):
        raise ValueError("ambiguous_document_test_plan")
    return result


def verify(log, cases, native=False):
    if native and "** TEST SUCCEEDED **" not in log:
        raise ValueError("native_document_test_not_successful")
    if re.search(r"Test Case .* (?:failed|skipped)", log):
        raise ValueError("document_test_failed_or_skipped")
    for suite, method in cases:
        matches = sum(bool(re.search(r"(?<!\w)" + re.escape(suite) + r"(?!\w)", line))
                      and bool(re.search(r"(?<!\w)" + re.escape(method) + r"(?!\w)", line))
                      and " passed " in line for line in log.splitlines())
        if matches != 1:
            raise ValueError("document_test_not_exactly_once:" + suite + "/" + method)
    return len(cases)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=["core", "native", "roundtrip"])
    parser.add_argument("log")
    parser.add_argument("--ownership-proof")
    parser.add_argument("--also-ai", action="store_true")
    args = parser.parse_args()
    log = Path(args.log).read_text(encoding="utf-8")
    count = verify(log, expected(args.kind), native=args.kind != "core")
    if args.also_ai:
        if args.kind != "core": raise ValueError("ai_gate_requires_core")
        cases = []
        for suite, size in AI.items():
            methods = re.findall(r"^\s*func (test\w+)\s*\(", (ROOT / "Tests/PivotCoreTests" / (suite + ".swift")).read_text(), re.M)
            if len(methods) != len(set(methods)) or len(methods) != size: raise ValueError("ai_test_source_drift")
            cases.extend((suite, method) for method in methods)
        if verify(log, cases) != 78: raise ValueError("ai_gate_incomplete")
    if args.kind == "roundtrip":
        if not args.ownership_proof: raise ValueError("missing_owned_simulator_proof")
        proof = json.loads(Path(args.ownership_proof).read_text())
        if proof.get("created") is not True or proof.get("deleted") is not True: raise ValueError("owned_simulator_cleanup_not_verified")
        uuid.UUID(proof["udid"])
        if not re.fullmatch(r"Pivot-Calendar-CI-[0-9]+-[0-9]+", proof.get("name", "")): raise ValueError("invalid_owned_simulator_name")
    print(f"Verified {count} exact {args.kind} document cases; no failures/skips")
