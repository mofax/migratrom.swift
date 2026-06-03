#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONTAINER_NAME="${MIGRATROM_PG_CONTAINER:-migratrom-swift-postgres}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-pw}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:16}"
KEEP_CONTAINER=0
STARTED_CONTAINER=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [-- swift-test-args...]

Start a throwaway Postgres (Docker) if needed, then run MigratromPostgresNIOTests.

Environment:
  MIGRATROM_TEST_DATABASE_URL  If set, Docker is skipped.
  MIGRATROM_PG_CONTAINER       Docker container name (default: migratrom-swift-postgres)
  POSTGRES_USER                Default: postgres
  POSTGRES_PASSWORD            Default: pw
  POSTGRES_DB                  Default: postgres
  POSTGRES_PORT                Host port (default: 5432)
  POSTGRES_IMAGE               Default: postgres:16

Options:
  --keep     Leave the Postgres container running on exit
  -h, --help Show this help

Examples:
  ./scripts/run-integration-tests.sh
  ./scripts/run-integration-tests.sh -- --filter ApplyIntegrationTests
  MIGRATROM_TEST_DATABASE_URL=postgres://... ./scripts/run-integration-tests.sh
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep)
            KEEP_CONTAINER=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

database_url() {
    printf 'postgres://%s:%s@127.0.0.1:%s/%s' \
        "$POSTGRES_USER" "$POSTGRES_PASSWORD" "$POSTGRES_PORT" "$POSTGRES_DB"
}

cleanup() {
    if [[ "$STARTED_CONTAINER" -eq 1 && "$KEEP_CONTAINER" -eq 0 ]]; then
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "error: docker not found; set MIGRATROM_TEST_DATABASE_URL or install Docker" >&2
        exit 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "error: docker daemon is not running" >&2
        exit 1
    fi
}

wait_for_container_postgres() {
    local attempt
    for attempt in $(seq 1 60); do
        if docker exec "$CONTAINER_NAME" pg_isready -U "$POSTGRES_USER" -q 2>/dev/null; then
            return 0
        fi
        sleep 0.5
    done
    echo "error: Postgres in container '$CONTAINER_NAME' did not become ready" >&2
    return 1
}

start_postgres_container() {
    require_docker

    if docker ps -q -f "name=^${CONTAINER_NAME}$" | grep -q .; then
        echo "using existing container: $CONTAINER_NAME" >&2
        return 0
    fi

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    echo "starting $POSTGRES_IMAGE on port $POSTGRES_PORT as $CONTAINER_NAME" >&2
    if ! docker run --rm -d \
        --name "$CONTAINER_NAME" \
        -e "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
        -e "POSTGRES_USER=$POSTGRES_USER" \
        -e "POSTGRES_DB=$POSTGRES_DB" \
        -p "${POSTGRES_PORT}:5432" \
        "$POSTGRES_IMAGE" >/dev/null; then
        echo "error: failed to start Postgres container" >&2
        exit 1
    fi

    STARTED_CONTAINER=1
    wait_for_container_postgres
}

resolve_database_url() {
    if [[ -n "${MIGRATROM_TEST_DATABASE_URL:-}" ]]; then
        printf '%s' "$MIGRATROM_TEST_DATABASE_URL"
        return 0
    fi

    start_postgres_container
    database_url
}

URL="$(resolve_database_url)"
export MIGRATROM_TEST_DATABASE_URL="$URL"

echo "MIGRATROM_TEST_DATABASE_URL=$URL" >&2
echo "running: swift test --filter MigratromPostgresNIOTests $*" >&2
swift test --filter MigratromPostgresNIOTests "$@"
