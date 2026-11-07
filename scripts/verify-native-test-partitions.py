"""Verify that SwiftPM's parallel and serial XCTest runs covered its full inventory."""
import collections
import json
import re
import sys
from pathlib import Path

MOTION = "RiftletUITests.ArrivalModesTests/"


def verify(directory):
    def read(name):
        return (directory / name).read_text()

    discovered = collections.Counter(line.strip() for line in read("discovered-tests.txt").splitlines()
                                     if "/" in line.strip())
    parallel = collections.Counter(re.findall(r"\[\d+/\d+\] Testing ([^\s]+)", read("swift-test.log")))
    outcomes = re.findall(r"Test Case '-\[(\S+) (\S+)\]' (passed|skipped|failed) ",
                          read("arrival-modes-serial.log"))
    serial = collections.Counter(f"{suite}/{method}" for suite, method, _ in outcomes)
    expected_serial = {test for test in discovered if test.startswith(MOTION)}
    expected_parallel = set(discovered) - expected_serial
    missing = sorted(set(discovered) - parallel.keys() - serial.keys())
    unexpected = sorted((parallel.keys() | serial.keys()) - set(discovered))
    if (not expected_parallel or not expected_serial or
        any(count != 1 for count in discovered.values()) or
        parallel != collections.Counter(expected_parallel) or serial != collections.Counter(expected_serial) or
        any(outcome == "failed" for _, _, outcome in outcomes)):
        raise SystemExit(f"Swift test partition mismatch: missing={missing}, unexpected={unexpected}, "
                         f"wrongParallel={sorted(parallel.keys() - expected_parallel)}, "
                         f"wrongSerial={sorted(serial.keys() - expected_serial)}, "
                         f"duplicates={sorted(n for n, c in (parallel+serial).items() if c != 1)}")
    return {"result": "PASS", "discovered": len(discovered), "parallel": len(parallel),
            "serial": len(serial), "serialOutcomes": dict(collections.Counter(o for _, _, o in outcomes))}


if __name__ == "__main__":
    print(json.dumps(verify(Path(sys.argv[1])), indent=2))
