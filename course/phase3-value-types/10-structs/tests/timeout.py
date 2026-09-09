"""Run one test program with a deadline; exit 124 when it does not terminate."""

import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: timeout.py <seconds> <command> [args ...]", file=sys.stderr)
        return 2
    try:
        return_code = subprocess.run(
            sys.argv[2:], timeout=float(sys.argv[1]), check=False
        ).returncode
        return return_code if return_code >= 0 else 128 - return_code
    except subprocess.TimeoutExpired:
        return 124


if __name__ == "__main__":
    raise SystemExit(main())
