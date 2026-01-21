#!/bin/bash

set -e

LOGS_DIR="logs"
S3_BUCKET="s3://pboyd.io-logs/cloudfront/"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  sync                  Sync logs from S3"
    echo "  raw [--from DATE] [--to DATE] [--path PATTERN]"
    echo "      [--referer PATTERN] [--user-agent PATTERN]"
    echo "                       View logs in goaccess"
    echo "                       DATE format: YYYY-MM-DD"
    echo "                       PATTERN: regex to match against field"
    echo "  view [--from DATE] [--to DATE] [--path PATTERN]"
    echo "       [--referer PATTERN] [--user-agent PATTERN]"
    echo "                        View logs in goaccess"
    echo "                        DATE format: YYYY-MM-DD"
    echo "                        PATTERN: regex to match against field"
    echo "  top-posts [-n NUM]    Output top NUM posts as Hugo template (default: 5)"
    exit 1
}

sync_logs() {
    echo "Syncing logs from S3..."
    aws s3 sync "$S3_BUCKET" "$LOGS_DIR/" --size-only
}

raw_logs() {
    local from_date=""
    local to_date=""
    local filter_field=""
    local filter_pattern=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from)
                from_date="$2"
                shift 2
                ;;
            --to)
                to_date="$2"
                shift 2
                ;;
            --path)
                filter_field=8
                filter_pattern="$2"
                shift 2
                ;;
            --referer)
                filter_field=10
                filter_pattern="$2"
                shift 2
                ;;
            --user-agent)
                filter_field=11
                filter_pattern="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    if [ ! -d "$LOGS_DIR" ] || [ -z "$(ls -A "$LOGS_DIR" 2>/dev/null)" ]; then
        echo "No logs found. Run '$0 sync' first."
        exit 1
    fi

    local files=()
    for f in "$LOGS_DIR"/*.gz; do
        # Extract date from filename (format: DISTID.YYYY-MM-DD-HH.hash.gz)
        local file_date
        file_date=$(basename "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)

        if [ -z "$file_date" ]; then
            continue
        fi

        if [ -n "$from_date" ] && [[ "$file_date" < "$from_date" ]]; then
            continue
        fi

        if [ -n "$to_date" ] && [[ "$file_date" > "$to_date" ]]; then
            continue
        fi

        files+=("$f")
    done

    if [ ${#files[@]} -eq 0 ]; then
        echo "No logs found matching the date range."
        exit 1
    fi

    echo "Processing ${#files[@]} log files..."
    if [ -n "$filter_pattern" ]; then
        gzip -dc "${files[@]}" | awk -v field="$filter_field" -v pattern="$filter_pattern" '$field ~ pattern'
    else
        gzip -dc "${files[@]}"
    fi
}

view_logs() {
    raw_logs "$@" | goaccess - --log-format CLOUDFRONT --http-protocol no
}

top_posts() {
    local num=5

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n)
                num="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    if [ ! -d "$LOGS_DIR" ] || [ -z "$(ls -A "$LOGS_DIR" 2>/dev/null)" ]; then
        echo "No logs found. Run '$0 sync' first." >&2
        exit 1
    fi

    local paths
    paths=$(gzip -dc "$LOGS_DIR"/*.gz | awk '$8 ~ /^\/posts\/[^\/]+\/?$/ {print $8}' | sort | uniq -c | sort -rn | head -n "$num" | awk '{print $2}')

    output=layouts/_partials/top-$num.html
    echo "Writing output to $output"

    (
        echo "<ul class=\"post-list\">"
        for path in $paths; do
            echo "  {{ with site.GetPage \"$path\" }}"
            echo "    <li>"
            echo "      {{ \$dateMachine := .Date | time.Format \"2006-01-02T15:04:05-07:00\" }}"
            echo "      {{ \$dateDisplay := .Date | time.Format \"2006-01-02\"}}"
            echo "      <time datetime=\"{{ \$dateMachine }}\">{{ \$dateDisplay }}</time><a class=\"title\" href=\"{{ .Permalink }}\">{{ .Title }}</a>"
            echo "    </li>"
            echo "  {{ end }}"

        done
        echo "</ul>"
    ) >$output
}

case "${1:-}" in
    sync)
        sync_logs
        ;;
    raw)
        shift
        raw_logs "$@"
        ;;
    view)
        shift
        view_logs "$@"
        ;;
    top-posts)
        shift
        top_posts "$@"
        ;;
    *)
        usage
        ;;
esac
