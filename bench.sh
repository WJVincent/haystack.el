#!/usr/bin/env bash
# Run the benchmark suite and print a markdown table of results.
# Paste the output into the Benchmarks section of README.md when
# updating timing numbers (e.g. before a release or after touching a hot path).
#
# Usage: ./bench.sh

set -euo pipefail

cd "$(dirname "$0")"

emacs --batch \
  -l ert \
  -l haystack.el \
  -l test/haystack-test.el \
  -l test/haystack-bench.el \
  -f ert-run-tests-batch-and-exit 2>&1 \
| grep "^haystack-bench:" \
| awk '{
    split($0, a, " \xe2\x80\x94 ");
    label = substr(a[1], 17);
    time  = a[2];
    printf "| %-45s | %s |\n", label, time
  }'
