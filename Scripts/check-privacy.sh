#!/bin/bash
# Fails if tracked files contain personal data: home-folder paths, the
# current user's name, or an Apple development team ID.
#
# Usage (from the repo root): Scripts/check-privacy.sh

set -u
status=0

check() {
    local label="$1" pattern="$2"
    local hits
    hits=$(git grep -n -I -i -E "$pattern" -- . ':!Scripts/check-privacy.sh' || true)
    if [ -n "$hits" ]; then
        echo "✗ $label:"
        echo "$hits" | sed 's/^/    /'
        status=1
    else
        echo "✓ No $label"
    fi
}

check "home-folder paths" '/Users/[A-Za-z0-9._-]+'
check "user name ($USER)" "\\b$USER\\b"

full_name=$(id -F 2>/dev/null || true)
if [ -n "$full_name" ]; then
    check "full name" "$full_name"
fi

# A DEVELOPMENT_TEAM line with a value is a team ID.
check "team IDs" 'DEVELOPMENT_TEAM *= *[A-Z0-9]{10}'

if git ls-files --error-unmatch Config/Local.xcconfig >/dev/null 2>&1; then
    echo "✗ Config/Local.xcconfig is tracked; it must stay git-ignored"
    status=1
else
    echo "✓ Config/Local.xcconfig is not tracked"
fi

exit $status
