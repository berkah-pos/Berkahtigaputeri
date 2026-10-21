#!/usr/bin/env python3
"""Run isolated workbook unit tests and emit a JUnit-compatible XML result."""

from __future__ import annotations

import argparse
import sys
import traceback
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any


class JUnitTextTestResult(unittest.TextTestResult):
    """Text test runner result that also records portable JUnit test cases."""

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self.junit_cases: list[tuple[unittest.case.TestCase, str, str | None]] = []

    def _record(self, test: unittest.case.TestCase, outcome: str, detail: str | None = None) -> None:
        self.junit_cases.append((test, outcome, detail))

    def addSuccess(self, test: unittest.case.TestCase) -> None:
        super().addSuccess(test)
        self._record(test, "success")

    def addFailure(self, test: unittest.case.TestCase, err: tuple[type[BaseException], BaseException, Any]) -> None:
        super().addFailure(test, err)
        self._record(test, "failure", self._exc_info_to_string(err, test))

    def addError(self, test: unittest.case.TestCase, err: tuple[type[BaseException], BaseException, Any]) -> None:
        super().addError(test, err)
        self._record(test, "error", self._exc_info_to_string(err, test))

    def addSkip(self, test: unittest.case.TestCase, reason: str) -> None:
        super().addSkip(test, reason)
        self._record(test, "skip", reason)

    def addExpectedFailure(
        self,
        test: unittest.case.TestCase,
        err: tuple[type[BaseException], BaseException, Any],
    ) -> None:
        super().addExpectedFailure(test, err)
        self._record(test, "skip", "Expected failure: " + self._exc_info_to_string(err, test))

    def addUnexpectedSuccess(self, test: unittest.case.TestCase) -> None:
        super().addUnexpectedSuccess(test)
        self._record(test, "failure", "Unexpected success for a test marked as expected to fail.")

    def addSubTest(
        self,
        test: unittest.case.TestCase,
        subtest: unittest.case.TestCase,
        err: tuple[type[BaseException], BaseException, Any] | None,
    ) -> None:
        super().addSubTest(test, subtest, err)
        if err is not None:
            self._record(test, "failure", self._exc_info_to_string(err, test))


def write_junit(result: JUnitTextTestResult, output: Path, elapsed_seconds: float) -> None:
    failures = sum(outcome == "failure" for _, outcome, _ in result.junit_cases)
    errors = sum(outcome == "error" for _, outcome, _ in result.junit_cases)
    skipped = sum(outcome == "skip" for _, outcome, _ in result.junit_cases)
    suite = ET.Element(
        "testsuite",
        {
            "name": "canonical-workbook",
            "tests": str(result.testsRun),
            "failures": str(failures),
            "errors": str(errors),
            "skipped": str(skipped),
            "time": f"{elapsed_seconds:.6f}",
        },
    )
    for test, outcome, detail in result.junit_cases:
        case = ET.SubElement(
            suite,
            "testcase",
            {
                "classname": test.__class__.__module__ + "." + test.__class__.__qualname__,
                "name": test._testMethodName,
            },
        )
        if outcome in {"failure", "error", "skip"}:
            element = ET.SubElement(case, outcome, {"message": (detail or outcome).splitlines()[0][:500]})
            element.text = detail or outcome
    output.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(suite).write(output, encoding="utf-8", xml_declaration=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test-dir", type=Path, default=Path("scripts/tests"))
    parser.add_argument("--pattern", default="test_*.py")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    import time

    started = time.monotonic()
    suite = unittest.defaultTestLoader.discover(
        str(args.test_dir),
        pattern=args.pattern,
        top_level_dir=".",
    )
    runner = unittest.TextTestRunner(
        stream=sys.stdout,
        verbosity=2,
        resultclass=JUnitTextTestResult,
    )
    result = runner.run(suite)
    write_junit(result, args.output, time.monotonic() - started)
    print(f"JUnit test report written: {args.output}")
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
