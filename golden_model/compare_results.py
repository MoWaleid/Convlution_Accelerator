"""Compare expected vs. actual hex files for RTL simulation verification.

Usage:
    python compare_results.py <expected.hex> <actual.hex>

Performs a strict bit-exact comparison of hex values line by line.
Reports the total number of mismatches and the location of the first
mismatch.  The comparison is case-insensitive to tolerate both uppercase
and lowercase hex digits.
"""
import sys
from pathlib import Path


def compare_files(expected_path: Path, actual_path: Path) -> bool:
    """Compare two hex vector files line by line (bit-exact).

    Args:
        expected_path: path to the golden reference hex file
        actual_path:   path to the RTL simulation output hex file

    Returns:
        True if all values match exactly, False otherwise.
    """
    if not expected_path.exists():
        print(f"  ERROR: Expected file not found: {expected_path}")
        return False
    if not actual_path.exists():
        print(f"  ERROR: Actual file not found: {actual_path}")
        return False

    with open(expected_path, "r") as f_exp, open(actual_path, "r") as f_act:
        exp_lines = [line.strip() for line in f_exp if line.strip()]
        act_lines = [line.strip() for line in f_act if line.strip()]

    if len(exp_lines) != len(act_lines):
        print(
            f"  FAIL: Line count mismatch — "
            f"expected {len(exp_lines)}, got {len(act_lines)}"
        )
        return False

    mismatches = 0
    first_mismatch = -1
    for i, (e, a) in enumerate(zip(exp_lines, act_lines)):
        if e.lower() != a.lower():
            if mismatches == 0:
                first_mismatch = i
            mismatches += 1

    if mismatches > 0:
        print(f"  FAIL: {mismatches}/{len(exp_lines)} values differ")
        print(
            f"  First mismatch at line {first_mismatch}: "
            f"expected 0x{exp_lines[first_mismatch]}, "
            f"got 0x{act_lines[first_mismatch]}"
        )
        return False

    print(f"  PASS: All {len(exp_lines)} values match")
    return True


def main() -> None:
    """Entry point: compare two hex files given as command-line arguments."""
    if len(sys.argv) != 3:
        print("Usage: python compare_results.py <expected.hex> <actual.hex>")
        sys.exit(1)

    expected = Path(sys.argv[1])
    actual   = Path(sys.argv[2])

    print(f"Comparing: {expected.name}  vs  {actual.name}")
    success = compare_files(expected, actual)
    if not success:
        sys.exit(1)


if __name__ == "__main__":
    main()
