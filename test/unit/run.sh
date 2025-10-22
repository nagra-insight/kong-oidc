#!/bin/bash
set -e

rm -f luacov.stats.out

# Run all test_*.lua files in test/unit (except test_schema.lua which requires Kong's full schema module)
for f in test/unit/test_*.lua; do
  # Skip test_schema.lua - run separately with run_schema_test.sh
  if [[ "$f" == *"test_schema.lua"* ]]; then
    continue
  fi
  (set -x
    lua -lluacov ${f} -o TAP --failure -v
  )
done
luacov
cat luacov.report.out
