#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

dockerfile="${repo_root}/java/Dockerfile"
entrypoint="${repo_root}/java/docker-entrypoint.sh"
workflow="${repo_root}/.github/workflows/java-release.yml"
readme="${repo_root}/README.md"
readme_zh="${repo_root}/README_zh.md"
cnb="${repo_root}/.cnb.yml"
cnb_trigger="${repo_root}/.cnb/web_trigger.yml"

test -f "${dockerfile}"
test -f "${entrypoint}"
test -f "${workflow}"

grep -q 'FROM eclipse-temurin:${JAVA_VERSION}-${JAVA_VARIANT}' "${dockerfile}"
grep -q 'ARG JAVA_VERSION' "${dockerfile}"
grep -q 'ARG JAVA_VARIANT=jdk-noble' "${dockerfile}"
grep -q 'COPY docker-entrypoint.sh /usr/local/bin/' "${dockerfile}"
grep -q 'chmod +x /usr/local/bin/docker-entrypoint.sh' "${dockerfile}"
grep -q 'ENTRYPOINT \["docker-entrypoint.sh"\]' "${dockerfile}"

grep -q "This image is maintained by 1Panel." "${entrypoint}"
grep -q "For support or issue discussion, please visit:" "${entrypoint}"
grep -q "https://github.com/1Panel-dev/1Panel/discussions" "${entrypoint}"
grep -q 'exec "$@"' "${entrypoint}"

grep -q 'name: Build Java Image' "${workflow}"
grep -q 'javaVersion:' "${workflow}"
grep -q 'javaVariant:' "${workflow}"
grep -q 'platforms:' "${workflow}"
grep -q 'context: java' "${workflow}"
grep -q 'file: java/Dockerfile' "${workflow}"
grep -q 'JAVA_VERSION=${{ github.event.inputs.javaVersion }}' "${workflow}"
grep -q 'JAVA_VARIANT=${{ github.event.inputs.javaVariant }}' "${workflow}"
grep -q '1panel/java:${{ github.event.inputs.javaVersion }}-jdk' "${workflow}"

grep -q '`1panel/java`' "${readme}"
grep -q '`1panel/java`' "${readme_zh}"

if grep -q 'java' "${cnb}" "${cnb_trigger}"; then
  echo "CNB files should not include Java build wiring yet" >&2
  exit 1
fi
