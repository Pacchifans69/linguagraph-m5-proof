#!/usr/bin/env bash
#
# LinguaGraph M5 — independent exact-candidate hosted Gate 2 proof.
#
# This script is the entire verification surface of the proof repository. It
# runs on a clean, independently hosted Linux machine (CircleCI `machine`
# executor, ubuntu-2404) and never mutates the application repository.
#
# Contract:
#
#   1. prove the proof source itself (repository, branch, HEAD == CIRCLE_SHA1,
#      tracked files, tracked worktree clean);
#   2. resolve the application refs with `git ls-remote`, fail closed unless the
#      M5 branch and `main` are the exact expected SHAs, fetch without tags and
#      check the candidate out DETACHED at the exact candidate SHA, then verify
#      HEAD, HEAD^{tree} and merge-base(candidate, frozen base);
#   3. record hosted environment provenance (Linux, CPU, memory, filesystem,
#      Docker, timezone, CircleCI build identity);
#   4. hash the frozen dependency manifests BEFORE installing anything;
#   5. install uv + Python 3.13 exactly, Node 24 exactly, and run real
#      PostgreSQL 18 in Docker, verified by `show server_version`;
#   6. `uv sync --frozen` and prove the resolved interpreter is Python 3.13;
#   7. migrate the EMPTY main service database to Alembic head (0006),
#      `alembic current` == "0006 (head)" and `alembic check` clean;
#   8. run the COMPLETE backend pytest suite against real PostgreSQL 18 and
#      fail closed if the log shows any skipped test;
#   9. run npm ci / lint / typecheck / test / build unchanged;
#  10. run the COMPLETE M0-M5 Playwright surface and prove every specification
#      actually executed;
#  11. prove zero leftover disposable `linguagraph_%` databases;
#  12. re-hash the dependency manifests and require exact before/after equality;
#  13. re-resolve the remote application refs and require the candidate,
#      the frozen base and the tracked candidate worktree to be unchanged.
#
# Every stage records name, label, start time, finish time and exit code in
# proof-artifacts/command-manifest.txt. The EXIT trap always writes the final
# identity, PostgreSQL evidence, cleanup and the SHA-256 artifact manifest, and
# a cleanup failure turns an otherwise successful proof into FAIL.
#
# A successful run is Gate 2 infrastructure evidence ONLY. It does not close
# G2-X01, does not replace Human Static Diff Review, and does not authorize a
# PR, a merge or milestone completion.

set -Eeuo pipefail
umask 022

PROOF_ROOT="$(pwd -P)"
ARTIFACT_DIR="${PROOF_ROOT}/proof-artifacts"
CANDIDATE_DIR="${PROOF_ROOT}/candidate"
POSTGRES_CONTAINER="linguagraph-m5-postgres18"

mkdir -p "${ARTIFACT_DIR}"
: > "${ARTIFACT_DIR}/command-manifest.txt"

utc_now() {
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

record_manifest() {
  printf '%s\n' "$*" >> "${ARTIFACT_DIR}/command-manifest.txt"
}

run_stage() {
  local slug="$1"
  local label="$2"
  shift 2

  local started finished rc
  started="$(utc_now)"
  printf '\n===== %s =====\n' "${label}"
  record_manifest "stage=${slug}"
  record_manifest "label=${label}"
  record_manifest "started_at=${started}"

  # The parent temporarily disables errexit so that a failing stage is recorded
  # and reported instead of killing the script before the EXIT trap can write
  # the artifacts. errexit MUST therefore be re-enabled INSIDE the stage
  # subshell: otherwise a mid-function assertion (a bare `test`, `grep -q`,
  # command substitution, ...) would be masked by whatever the stage happens to
  # run last, and the proof could fail open.
  set +e
  ( set -e; "$@" ) 2>&1 | tee "${ARTIFACT_DIR}/${slug}.log"
  rc="${PIPESTATUS[0]}"
  set -e

  finished="$(utc_now)"
  record_manifest "finished_at=${finished}"
  record_manifest "exit_code=${rc}"
  record_manifest "---"

  if [ "${rc}" -ne 0 ]; then
    printf 'Stage failed: %s (exit %s)\n' "${label}" "${rc}"
  fi
  return "${rc}"
}

load_uv() {
  export PATH="${HOME}/.local/bin:${PATH}"
  command -v uv >/dev/null
}

load_node() {
  export NVM_DIR="${HOME}/.nvm"
  # shellcheck disable=SC1091
  . "${NVM_DIR}/nvm.sh" --no-use
  nvm use --silent 24 >/dev/null
  test "$(node -p 'process.versions.node.split(".")[0]')" = "24"
}

finalize() {
  local rc="$?"
  local cleanup_rc=0
  trap - EXIT
  set +e

  {
    echo "finished_at=$(utc_now)"
    echo "script_exit_code_before_cleanup=${rc}"
    echo "circle_build_url=${CIRCLE_BUILD_URL:-unset}"
    echo "circle_workflow_id=${CIRCLE_WORKFLOW_ID:-unset}"
    echo "circle_build_num=${CIRCLE_BUILD_NUM:-unset}"
    echo "circle_job=${CIRCLE_JOB:-unset}"
    echo "circle_sha1=${CIRCLE_SHA1:-unset}"
  } > "${ARTIFACT_DIR}/final-summary.txt"

  git -C "${PROOF_ROOT}" status --short --untracked-files=all \
    > "${ARTIFACT_DIR}/final-proof-repository-status.txt" 2>&1
  git -C "${PROOF_ROOT}" rev-parse HEAD \
    > "${ARTIFACT_DIR}/final-proof-repository-head.txt" 2>&1
  git -C "${PROOF_ROOT}" rev-parse 'HEAD^{tree}' \
    > "${ARTIFACT_DIR}/final-proof-repository-tree.txt" 2>&1

  if git -C "${CANDIDATE_DIR}" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "${CANDIDATE_DIR}" status --short --untracked-files=all \
      > "${ARTIFACT_DIR}/final-candidate-status.txt" 2>&1
    git -C "${CANDIDATE_DIR}" rev-parse HEAD \
      > "${ARTIFACT_DIR}/final-candidate-head.txt" 2>&1
    git -C "${CANDIDATE_DIR}" rev-parse 'HEAD^{tree}' \
      > "${ARTIFACT_DIR}/final-candidate-tree.txt" 2>&1
    git -C "${CANDIDATE_DIR}" diff --stat \
      > "${ARTIFACT_DIR}/final-candidate-diff-stat.txt" 2>&1
    git -C "${CANDIDATE_DIR}" diff --cached --stat \
      > "${ARTIFACT_DIR}/final-candidate-cached-diff-stat.txt" 2>&1
  fi

  if docker inspect "${POSTGRES_CONTAINER}" >/dev/null 2>&1; then
    docker inspect "${POSTGRES_CONTAINER}" \
      > "${ARTIFACT_DIR}/postgres-container-inspect.json" 2>&1
    docker logs "${POSTGRES_CONTAINER}" \
      > "${ARTIFACT_DIR}/postgres-container.log" 2>&1
    docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d postgres -Atc \
      "select datname from pg_database where datname like 'linguagraph_%' order by datname;" \
      > "${ARTIFACT_DIR}/final-disposable-databases.txt" 2>&1

    docker rm -f "${POSTGRES_CONTAINER}" >/dev/null 2>&1
    cleanup_rc="$?"
    echo "postgres_container_cleanup_exit_code=${cleanup_rc}" \
      >> "${ARTIFACT_DIR}/final-summary.txt"
    if [ "${rc}" -eq 0 ] && [ "${cleanup_rc}" -ne 0 ]; then
      rc=1
    fi
  else
    echo "postgres_container_cleanup=not_present" \
      >> "${ARTIFACT_DIR}/final-summary.txt"
  fi

  if [ -d "${CANDIDATE_DIR}/apps/web/test-results" ]; then
    tar -czf "${ARTIFACT_DIR}/playwright-test-results.tgz" \
      -C "${CANDIDATE_DIR}/apps/web" test-results
  fi

  echo "proof_exit_code=${rc}" >> "${ARTIFACT_DIR}/final-summary.txt"
  if [ "${rc}" -eq 0 ]; then
    echo "proof_result=PASS" >> "${ARTIFACT_DIR}/final-summary.txt"
  else
    echo "proof_result=FAIL" >> "${ARTIFACT_DIR}/final-summary.txt"
  fi

  (
    cd "${ARTIFACT_DIR}"
    find . -type f ! -name artifact-manifest.sha256 -print0 \
      | sort -z \
      | xargs -0 sha256sum \
      > artifact-manifest.sha256
  )

  exit "${rc}"
}

trap finalize EXIT

require_environment() {
  local name
  for name in \
    EXPECTED_PROOF_REPOSITORY \
    EXPECTED_PROOF_BRANCH \
    CANDIDATE_REPOSITORY_URL \
    EXPECTED_CANDIDATE_REPOSITORY \
    EXPECTED_CANDIDATE_BRANCH \
    EXPECTED_CANDIDATE_SHA \
    EXPECTED_CANDIDATE_TREE \
    EXPECTED_FROZEN_BASE \
    EXPECTED_MAIN_SHA \
    EXPECTED_ALEMBIC_HEAD \
    DATABASE_URL \
    TEST_DATABASE_URL \
    CIRCLE_PROJECT_USERNAME \
    CIRCLE_PROJECT_REPONAME \
    CIRCLE_BRANCH \
    CIRCLE_SHA1; do
    test -n "${!name:-}" || {
      echo "Required environment variable is missing: ${name}"
      return 1
    }
  done
}

capture_environment() {
  local timezone_value
  timezone_value="$(timedatectl show -p Timezone --value 2>/dev/null | head -n1 || true)"
  if [ -z "${timezone_value}" ]; then
    timezone_value="$(head -n1 /etc/timezone 2>/dev/null || true)"
  fi
  if [ -z "${timezone_value}" ]; then
    timezone_value="$(date +%Z)"
  fi

  {
    echo "captured_at=$(utc_now)"
    uname -a
    echo
    cat /etc/os-release
    echo
    echo "architecture=$(uname -m)"
    echo "processor_count=$(getconf _NPROCESSORS_ONLN)"
    echo "system_timezone=${timezone_value}"
    echo "system_utc_offset=$(date -u +%z)"
    echo "circle_build_url=${CIRCLE_BUILD_URL:-unset}"
    echo "circle_workflow_id=${CIRCLE_WORKFLOW_ID:-unset}"
    echo "circle_build_num=${CIRCLE_BUILD_NUM:-unset}"
    echo "circle_job=${CIRCLE_JOB:-unset}"
    echo "circle_node_index=${CIRCLE_NODE_INDEX:-unset}"
    echo "circle_node_total=${CIRCLE_NODE_TOTAL:-unset}"
    echo
    free -h
    echo
    df -h .
    echo
    docker version
  } | tee "${ARTIFACT_DIR}/environment.txt"
}

verify_proof_source() {
  local actual_repository actual_head actual_tree
  actual_repository="${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}"
  actual_head="$(git -C "${PROOF_ROOT}" rev-parse HEAD)"
  actual_tree="$(git -C "${PROOF_ROOT}" rev-parse 'HEAD^{tree}')"

  git -C "${PROOF_ROOT}" ls-files > "${ARTIFACT_DIR}/proof-tracked-files.txt"

  {
    printf '%s\n' \
      "expected_proof_repository=${EXPECTED_PROOF_REPOSITORY}" \
      "actual_proof_repository=${actual_repository}" \
      "expected_proof_branch=${EXPECTED_PROOF_BRANCH}" \
      "actual_proof_branch=${CIRCLE_BRANCH}" \
      "circle_sha1=${CIRCLE_SHA1}" \
      "proof_head=${actual_head}" \
      "proof_tree=${actual_tree}" \
      "proof_origin=$(git -C "${PROOF_ROOT}" remote get-url origin)" \
      "proof_tracked_worktree_clean=$(git -C "${PROOF_ROOT}" status --porcelain --untracked-files=no | wc -l)"
    echo "--- proof tracked file hashes ---"
    ( cd "${PROOF_ROOT}" && sha256sum .circleci/config.yml .gitignore README.md scripts/run-m5-proof.sh )
    echo "--- proof tracked files ---"
    cat "${ARTIFACT_DIR}/proof-tracked-files.txt"
  } | tee "${ARTIFACT_DIR}/proof-provenance.txt"

  test "${actual_repository}" = "${EXPECTED_PROOF_REPOSITORY}"
  test "${CIRCLE_BRANCH}" = "${EXPECTED_PROOF_BRANCH}"
  test "${actual_head}" = "${CIRCLE_SHA1}"
  test -f "${PROOF_ROOT}/.circleci/config.yml"
  test -f "${PROOF_ROOT}/scripts/run-m5-proof.sh"
  test -z "$(git -C "${PROOF_ROOT}" status --porcelain --untracked-files=no)"
}

checkout_candidate() {
  local remote_line remote_sha remote_ref main_line main_sha main_ref
  local actual_head actual_tree merge_base
  test ! -e "${CANDIDATE_DIR}"

  git init "${CANDIDATE_DIR}"
  git -C "${CANDIDATE_DIR}" remote add origin "${CANDIDATE_REPOSITORY_URL}"

  remote_line="$(git -C "${CANDIDATE_DIR}" ls-remote --refs origin "refs/heads/${EXPECTED_CANDIDATE_BRANCH}")"
  test -n "${remote_line}"
  read -r remote_sha remote_ref <<< "${remote_line}"
  test "${remote_ref}" = "refs/heads/${EXPECTED_CANDIDATE_BRANCH}"
  test "${remote_sha}" = "${EXPECTED_CANDIDATE_SHA}"

  main_line="$(git -C "${CANDIDATE_DIR}" ls-remote --refs origin refs/heads/main)"
  test -n "${main_line}"
  read -r main_sha main_ref <<< "${main_line}"
  test "${main_ref}" = "refs/heads/main"
  test "${main_sha}" = "${EXPECTED_MAIN_SHA}"

  git -C "${CANDIDATE_DIR}" fetch --no-tags --depth=64 origin \
    "refs/heads/${EXPECTED_CANDIDATE_BRANCH}:refs/remotes/origin/${EXPECTED_CANDIDATE_BRANCH}"
  test "$(git -C "${CANDIDATE_DIR}" rev-parse "refs/remotes/origin/${EXPECTED_CANDIDATE_BRANCH}")" \
    = "${EXPECTED_CANDIDATE_SHA}"
  git -C "${CANDIDATE_DIR}" -c advice.detachedHead=false checkout --detach \
    "${EXPECTED_CANDIDATE_SHA}"

  actual_head="$(git -C "${CANDIDATE_DIR}" rev-parse HEAD)"
  actual_tree="$(git -C "${CANDIDATE_DIR}" rev-parse 'HEAD^{tree}')"
  git -C "${CANDIDATE_DIR}" cat-file -e "${EXPECTED_FROZEN_BASE}^{commit}"
  merge_base="$(git -C "${CANDIDATE_DIR}" merge-base "${EXPECTED_CANDIDATE_SHA}" "${EXPECTED_FROZEN_BASE}")"

  printf '%s\n' \
    "expected_candidate_repository=${EXPECTED_CANDIDATE_REPOSITORY}" \
    "candidate_origin=$(git -C "${CANDIDATE_DIR}" remote get-url origin)" \
    "expected_candidate_branch=${EXPECTED_CANDIDATE_BRANCH}" \
    "remote_candidate_branch_sha=${remote_sha}" \
    "expected_candidate_sha=${EXPECTED_CANDIDATE_SHA}" \
    "candidate_head=${actual_head}" \
    "expected_candidate_tree=${EXPECTED_CANDIDATE_TREE}" \
    "candidate_tree=${actual_tree}" \
    "expected_main_sha=${EXPECTED_MAIN_SHA}" \
    "remote_main_sha=${main_sha}" \
    "expected_frozen_base=${EXPECTED_FROZEN_BASE}" \
    "candidate_merge_base=${merge_base}" \
    "candidate_object_type=$(git -C "${CANDIDATE_DIR}" cat-file -t "${actual_head}")" \
    | tee "${ARTIFACT_DIR}/candidate-provenance.txt"

  test "${actual_head}" = "${EXPECTED_CANDIDATE_SHA}"
  test "${actual_tree}" = "${EXPECTED_CANDIDATE_TREE}"
  test "${merge_base}" = "${EXPECTED_FROZEN_BASE}"
  test -z "$(git -C "${CANDIDATE_DIR}" status --porcelain)"

  if git -C "${CANDIDATE_DIR}" cat-file -e \
    "${EXPECTED_CANDIDATE_SHA}:.circleci/config.yml" 2>/dev/null; then
    echo "Candidate unexpectedly contains the external CircleCI configuration."
    return 1
  fi
}

install_uv_python() {
  curl -LsSf https://astral.sh/uv/install.sh | sh
  load_uv
  uv python install 3.13

  local python_bin python_version
  python_bin="$(uv python find 3.13)"
  python_version="$("${python_bin}" -c 'import platform, sys; assert sys.version_info[:2] == (3, 13); print(platform.python_version())')"

  printf 'uv=%s\npython=%s\n' "$(uv --version)" "${python_version}" \
    | tee -a "${ARTIFACT_DIR}/runtime-versions.txt"
}

install_node() {
  export NVM_DIR="${HOME}/.nvm"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh | bash
  # shellcheck disable=SC1091
  . "${NVM_DIR}/nvm.sh" --no-use
  nvm install 24
  nvm use --silent 24 >/dev/null

  local node_version node_major npm_version
  node_version="$(node --version)"
  node_major="$(node -p 'process.versions.node.split(".")[0]')"
  npm_version="$(npm --version)"
  test "${node_major}" = "24"

  printf 'node=%s\nnpm=%s\n' "${node_version}" "${npm_version}" \
    | tee -a "${ARTIFACT_DIR}/runtime-versions.txt"
}

start_postgresql() {
  docker pull postgres:18
  docker run --detach \
    --name "${POSTGRES_CONTAINER}" \
    --env POSTGRES_USER=postgres \
    --env POSTGRES_PASSWORD=postgres \
    --env POSTGRES_DB=postgres \
    --publish 5432:5432 \
    postgres:18

  local ready=0 attempt postgres_version client_version image_id image_digest
  for attempt in $(seq 1 30); do
    if docker exec "${POSTGRES_CONTAINER}" pg_isready -U postgres -d postgres >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 2
  done
  test "${ready}" = "1"

  postgres_version="$(docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d postgres -Atc 'show server_version')"
  client_version="$(docker exec "${POSTGRES_CONTAINER}" psql --version)"
  case "${postgres_version}" in
    18.*) ;;
    *)
      echo "PostgreSQL major-version mismatch: ${postgres_version}"
      return 1
      ;;
  esac

  image_id="$(docker image inspect postgres:18 --format '{{.Id}}')"
  image_digest="$(docker image inspect postgres:18 --format '{{join .RepoDigests ","}}')"
  printf 'postgresql=%s\npostgresql_client=%s\npostgres_image_id=%s\npostgres_image_digest=%s\n' \
    "${postgres_version}" "${client_version}" "${image_id}" "${image_digest}" \
    | tee -a "${ARTIFACT_DIR}/runtime-versions.txt"
}

capture_lock_hashes() {
  local phase="$1"
  {
    echo "phase=${phase}"
    sha256sum \
      "${CANDIDATE_DIR}/apps/api/pyproject.toml" \
      "${CANDIDATE_DIR}/apps/api/uv.lock" \
      "${CANDIDATE_DIR}/apps/web/package.json" \
      "${CANDIDATE_DIR}/apps/web/package-lock.json"
    echo "---"
  } | tee -a "${ARTIFACT_DIR}/dependency-lock-hashes.txt"
}

backend_sync() {
  load_uv
  cd "${CANDIDATE_DIR}/apps/api"
  uv sync --frozen
  uv run python -c \
    'import platform, sys; assert sys.version_info[:2] == (3, 13); print("backend-python=" + platform.python_version())'
}

migration_safety() {
  load_uv
  cd "${CANDIDATE_DIR}/apps/api"

  local public_tables_before public_tables_after
  public_tables_before="$(docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d postgres -Atc \
    "select count(*) from information_schema.tables where table_schema = 'public';")"
  echo "public_tables_before=${public_tables_before}"
  test "${public_tables_before}" = "0"

  uv run alembic upgrade head
  uv run alembic current | tee "${ARTIFACT_DIR}/alembic-current.txt"
  grep -q "${EXPECTED_ALEMBIC_HEAD} (head)" "${ARTIFACT_DIR}/alembic-current.txt"
  uv run alembic check

  public_tables_after="$(docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d postgres -Atc \
    "select count(*) from information_schema.tables where table_schema = 'public';")"
  echo "public_tables_after=${public_tables_after}"
}

backend_tests() {
  load_uv
  cd "${CANDIDATE_DIR}/apps/api"
  uv run pytest -q
}

zero_skip_guard() {
  if grep -qi "skipped" "${ARTIFACT_DIR}/backend-tests.log"; then
    echo "Backend suite reported skipped tests; real-PostgreSQL proof is invalid."
    return 1
  fi
  tail -10 "${ARTIFACT_DIR}/backend-tests.log"
}

frontend_install() {
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  npm ci
}

frontend_lint() {
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  npm run lint
}

frontend_typecheck() {
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  npm run typecheck
}

frontend_tests() {
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  npm run test
}

frontend_build() {
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  npm run build
}

playwright_install() {
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  npx playwright install --with-deps chromium
}

playwright_e2e() {
  load_uv
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  CI=1 npx playwright test \
    e2e/golden-path.spec.ts \
    e2e/unicode.spec.ts \
    e2e/segmentation.spec.ts \
    e2e/token-segmentation.spec.ts \
    e2e/lemma-annotation.spec.ts \
    e2e/pos-annotation.spec.ts
}

playwright_surface_guard() {
  local spec missing=0
  for spec in \
    golden-path.spec.ts \
    unicode.spec.ts \
    segmentation.spec.ts \
    token-segmentation.spec.ts \
    lemma-annotation.spec.ts \
    pos-annotation.spec.ts; do
    if grep -q "${spec}" "${ARTIFACT_DIR}/playwright-e2e.log"; then
      echo "executed_spec=${spec}"
    else
      echo "missing_spec=${spec}"
      missing=1
    fi
  done
  tail -20 "${ARTIFACT_DIR}/playwright-e2e.log"
  test "${missing}" = "0"
}

prove_disposable_cleanup() {
  local leftovers
  leftovers="$(docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d postgres -Atc \
    "select datname from pg_database where datname like 'linguagraph_%' order by datname;")"
  printf '%s\n' "${leftovers}" | tee "${ARTIFACT_DIR}/post-e2e-databases.txt"
  if [ -n "${leftovers}" ]; then
    echo "Disposable LinguaGraph databases remain after E2E."
    return 1
  fi
}

verify_final_integrity() {
  local final_remote_line final_remote_sha final_remote_ref
  local final_main_line final_main_sha final_main_ref
  local actual_head actual_tree merge_base
  final_remote_line="$(git -C "${CANDIDATE_DIR}" ls-remote --refs origin \
    "refs/heads/${EXPECTED_CANDIDATE_BRANCH}")"
  read -r final_remote_sha final_remote_ref <<< "${final_remote_line}"

  final_main_line="$(git -C "${CANDIDATE_DIR}" ls-remote --refs origin refs/heads/main)"
  read -r final_main_sha final_main_ref <<< "${final_main_line}"

  actual_head="$(git -C "${CANDIDATE_DIR}" rev-parse HEAD)"
  actual_tree="$(git -C "${CANDIDATE_DIR}" rev-parse 'HEAD^{tree}')"
  merge_base="$(git -C "${CANDIDATE_DIR}" merge-base "${actual_head}" "${EXPECTED_FROZEN_BASE}")"

  printf '%s\n' \
    "final_remote_ref=${final_remote_ref}" \
    "final_remote_branch_sha=${final_remote_sha}" \
    "expected_candidate_sha=${EXPECTED_CANDIDATE_SHA}" \
    "final_candidate_head=${actual_head}" \
    "expected_candidate_tree=${EXPECTED_CANDIDATE_TREE}" \
    "final_candidate_tree=${actual_tree}" \
    "final_main_ref=${final_main_ref}" \
    "final_main_sha=${final_main_sha}" \
    "expected_main_sha=${EXPECTED_MAIN_SHA}" \
    "expected_frozen_base=${EXPECTED_FROZEN_BASE}" \
    "final_candidate_merge_base=${merge_base}" \
    | tee "${ARTIFACT_DIR}/final-integrity.txt"

  git -C "${CANDIDATE_DIR}" status --short --untracked-files=all \
    | tee "${ARTIFACT_DIR}/candidate-status-after-proof.txt"

  test "${final_remote_ref}" = "refs/heads/${EXPECTED_CANDIDATE_BRANCH}"
  test "${final_remote_sha}" = "${EXPECTED_CANDIDATE_SHA}"
  test "${final_main_ref}" = "refs/heads/main"
  test "${final_main_sha}" = "${EXPECTED_MAIN_SHA}"
  test "${actual_head}" = "${EXPECTED_CANDIDATE_SHA}"
  test "${actual_tree}" = "${EXPECTED_CANDIDATE_TREE}"
  test "${merge_base}" = "${EXPECTED_FROZEN_BASE}"
  test -z "$(git -C "${CANDIDATE_DIR}" status --porcelain --untracked-files=no)"
  git -C "${CANDIDATE_DIR}" diff --quiet
  git -C "${CANDIDATE_DIR}" diff --cached --quiet
  test -z "$(git -C "${PROOF_ROOT}" status --porcelain --untracked-files=no)"
}

run_stage "environment-contract" "Environment — required variables" require_environment
run_stage "environment" "Environment — hosted Linux manifest" capture_environment
run_stage "proof-provenance" "Provenance — proof repository" verify_proof_source
run_stage "candidate-checkout" "Provenance — exact M5 candidate and frozen base" checkout_candidate
run_stage "dependency-hashes-before" "Integrity — dependency hashes before execution" capture_lock_hashes before
run_stage "runtime-python" "Runtime — uv and Python 3.13" install_uv_python
run_stage "runtime-node" "Runtime — Node 24" install_node
run_stage "runtime-postgresql" "Runtime — PostgreSQL 18" start_postgresql
run_stage "backend-sync" "Backend — uv sync --frozen" backend_sync
run_stage "migration" "Backend — empty database to 0006 head/current/check" migration_safety
run_stage "backend-tests" "Backend — full real-PostgreSQL pytest suite" backend_tests
run_stage "backend-zero-skip" "Backend — zero skipped-test guard" zero_skip_guard
run_stage "frontend-install" "Frontend — npm ci" frontend_install
run_stage "frontend-lint" "Frontend — lint" frontend_lint
run_stage "frontend-typecheck" "Frontend — typecheck" frontend_typecheck
run_stage "frontend-tests" "Frontend — Vitest/RTL" frontend_tests
run_stage "frontend-build" "Frontend — production build" frontend_build
run_stage "playwright-install" "E2E — install Chromium and system dependencies" playwright_install
run_stage "playwright-e2e" "E2E — golden path, Unicode, M2/M3 segmentation, M4 lemma and M5 POS" playwright_e2e
run_stage "playwright-surface-guard" "E2E — prove the complete M0-M5 specification surface executed" playwright_surface_guard
run_stage "database-cleanup" "E2E — prove disposable database cleanup" prove_disposable_cleanup
run_stage "dependency-hashes-after" "Integrity — dependency hashes after execution" capture_lock_hashes after
run_stage "final-integrity" "Integrity — candidate, main, and proof source preserved" verify_final_integrity

echo "All M5 exact-candidate semantic gates completed successfully."
