#!/bin/bash
set -e

. .env

# Build the test image
docker build \
  --build-arg KONG_BASE_TAG=${KONG_BASE_TAG} \
  -t ${BUILD_IMG_NAME} \
  -f ${UNIT_PATH}/Dockerfile .

# Run tests and capture exit code
# Note: Using --rm without -it to work in CI environments without TTY
docker run --rm ${BUILD_IMG_NAME} /bin/bash test/unit/run.sh
TEST_EXIT_CODE=$?

if [ $TEST_EXIT_CODE -ne 0 ]; then
  echo "Tests FAILED with exit code $TEST_EXIT_CODE"
  exit $TEST_EXIT_CODE
fi

echo "Done"
