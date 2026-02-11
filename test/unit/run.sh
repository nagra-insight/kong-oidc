#!/bin/bash
set -e

rm -f luacov.stats.out

FAILED=0

# Run all test_*.lua files in test/unit (except test_schema.lua which requires Kong's full schema module)
for f in test/unit/test_*.lua; do
  # Skip test_schema.lua - run separately with run_schema_test.sh
  if [[ "$f" == *"test_schema.lua"* ]]; then
    continue
  fi
  echo "Running $f..."
  set +e
  lua -lluacov ${f} -o TAP --failure -v
  if [ $? -ne 0 ]; then
    FAILED=1
    echo "FAILED: $f"
  fi
  set -e
done

luacov
cat luacov.report.out

if [ $FAILED -ne 0 ]; then
  echo ""
  echo "ERROR: One or more tests failed!"
  exit 1
fi

echo ""
echo "All tests passed!"
