#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE}")/lib/init.sh"

SCRIPT_ROOT=$(dirname ${BASH_SOURCE})/..
CODEGEN_PKG=${CODEGEN_PKG:-$(cd ${SCRIPT_ROOT}; ls -d -1 ./vendor/k8s.io/kube-openapi 2>/dev/null || echo ../../../k8s.io/kube-openapi)}

go install ./${CODEGEN_PKG}/cmd/openapi-gen

function codegen::join() { local IFS="$1"; shift; echo "$*"; }

ORIGIN_PREFIX="${OS_GO_PACKAGE}/"

INPUT_DIRS=(
  # kube apis
  $(
    grep --color=never -rl '+k8s:openapi-gen=' vendor/k8s.io/kubernetes | \
    xargs -n1 dirname | \
    sed "s,^vendor/,," | \
    sort -u | \
    sed '/^k8s\.io\/kubernetes\/build\/root$/d' | \
    sed '/^k8s\.io\/kubernetes$/d' | \
    sed '/^k8s\.io\/kubernetes\/staging$/d' | \
    sed 's,k8s\.io/kubernetes/staging/src/,,'
  )

  # origin apis
  $(
    grep --color=never -rl '+k8s:openapi-gen=' vendor/github.com/openshift/api | \
    xargs -n1 dirname | \
    sed "s,^vendor/,," | \
    sort -u
  )
)

INPUT_DIRS=$(IFS=,; echo "${INPUT_DIRS[*]}")

REPORT_FILENAME=$(mktemp)
KNOWN_VIOLATION_FILENAME=${SCRIPT_ROOT}/hack/openapi-violation.list

echo "Generating openapi"
${GOPATH}/bin/openapi-gen \
  --logtostderr \
  --build-tag=ignore_autogenerated_openshift \
  --output-file-base zz_generated.openapi \
  --go-header-file ${SCRIPT_ROOT}/hack/boilerplate.txt \
  --output-base="${GOPATH}/src" \
  --input-dirs "${INPUT_DIRS}" \
  --output-package "${ORIGIN_PREFIX}pkg/openapi" \
  --report-filename "${REPORT_FILENAME}" \
  "$@"

if ! diff -q "${REPORT_FILENAME}" "${KNOWN_VIOLATION_FILENAME}" ; then
	os::log::fatal "Error: API rules check failed. Reported violations ${REPORT_FILENAME} differ from known violations ${KNOWN_VIOLATION_FILENAME}. Please fix API source file if new violation is detected, or update known violations ${KNOWN_VIOLATION_FILENAME} if existing violation is being fixed. Please refer to api/api-rules/README.md and https://github.com/kubernetes/kube-openapi/tree/master/pkg/generators/rules for more information about the API rules being enforced."
fi
