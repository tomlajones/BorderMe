#!/bin/bash

set -u

APP_NAME="BorderMe"
ENGINE="${BORDERME_ENGINE:-$HOME/Library/Services/BorderMe.workflow/Contents/Resources/borderme-engine}"
NO_NOTIFY="${BORDERME_NO_NOTIFY:-0}"
CURRENT_TEMP=""
FAILURE_DETAILS=""
FAILURE_COUNT=0
SUCCESS_COUNT=0

cleanup() {
    if [ -n "$CURRENT_TEMP" ] && [ -e "$CURRENT_TEMP" ]; then
        /bin/rm -f "$CURRENT_TEMP"
    fi
}
trap cleanup EXIT HUP INT TERM

show_alert() {
    if [ "$NO_NOTIFY" = "1" ]; then
        /bin/echo "$1" >&2
        return
    fi

    /usr/bin/osascript - "$1" <<'APPLESCRIPT' >/dev/null
on run argv
    display dialog (item 1 of argv) with title "BorderMe" buttons {"OK"} default button "OK" with icon caution
end run
APPLESCRIPT
}

show_notification() {
    if [ "$NO_NOTIFY" = "1" ]; then
        return
    fi

    /usr/bin/osascript - "$1" <<'APPLESCRIPT' >/dev/null
on run argv
    display notification (item 1 of argv) with title "BorderMe"
end run
APPLESCRIPT
}

choose_border() {
    case "${BORDERME_BORDER:-}" in
        small|medium|large)
            /bin/echo "$BORDERME_BORDER"
            return
            ;;
    esac

    /usr/bin/osascript <<'APPLESCRIPT'
try
    set choices to {"Small (2%)", "Medium (5%)", "Large (8%)"}
    set picked to choose from list choices with title "BorderMe" with prompt "Choose border thickness:" default items {"Medium (5%)"} OK button name "Continue" cancel button name "Cancel"
    if picked is false then return "cancel"
    set selectedChoice to item 1 of picked
    if selectedChoice starts with "Small" then return "small"
    if selectedChoice starts with "Medium" then return "medium"
    return "large"
on error number -128
    return "cancel"
end try
APPLESCRIPT
}

choose_output() {
    case "${BORDERME_OUTPUT:-}" in
        small|medium|large|instagram-portrait|instagram-landscape)
            /bin/echo "$BORDERME_OUTPUT"
            return
            ;;
    esac

    /usr/bin/osascript <<'APPLESCRIPT'
try
    set choices to {"Small - up to 1200 px", "Medium - up to 2400 px", "Large - original resolution", "Instagram Portrait - 1080 x 1440", "Instagram Landscape - 1080 x 566"}
    set picked to choose from list choices with title "BorderMe" with prompt "Choose output size:" default items {"Medium - up to 2400 px"} OK button name "Create" cancel button name "Cancel"
    if picked is false then return "cancel"
    set selectedChoice to item 1 of picked
    if selectedChoice starts with "Small" then return "small"
    if selectedChoice starts with "Medium" then return "medium"
    if selectedChoice starts with "Large" then return "large"
    if selectedChoice starts with "Instagram Portrait" then return "instagram-portrait"
    return "instagram-landscape"
on error number -128
    return "cancel"
end try
APPLESCRIPT
}

unique_output_path() {
    input="$1"
    border="$2"
    preset="$3"
    directory=$(/usr/bin/dirname "$input")
    filename=$(/usr/bin/basename "$input")

    case "$filename" in
        *.*) stem="${filename%.*}" ;;
        *) stem="$filename" ;;
    esac
    if [ -z "$stem" ]; then
        stem="image"
    fi

    candidate="$directory/${stem}-border-${border}-${preset}.jpg"
    number=2
    while [ -e "$candidate" ]; do
        candidate="$directory/${stem}-border-${border}-${preset}-${number}.jpg"
        number=$((number + 1))
    done
    /bin/echo "$candidate"
}

record_failure() {
    input="$1"
    reason="$2"
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    if [ "$FAILURE_COUNT" -le 8 ]; then
        filename=$(/usr/bin/basename "$input")
        if [ -n "$FAILURE_DETAILS" ]; then
            FAILURE_DETAILS="$FAILURE_DETAILS
"
        fi
        FAILURE_DETAILS="${FAILURE_DETAILS}${filename}: ${reason}"
    fi
}

if [ "$#" -eq 0 ]; then
    show_alert "Select one or more image files in Finder, then run BorderMe again."
    exit 1
fi

if [ ! -x "$ENGINE" ]; then
    show_alert "The BorderMe image engine is missing. Reinstall BorderMe.workflow and try again."
    exit 1
fi

BORDER=$(choose_border)
if [ "$BORDER" = "cancel" ] || [ -z "$BORDER" ]; then
    exit 0
fi

OUTPUT_PRESET=$(choose_output)
if [ "$OUTPUT_PRESET" = "cancel" ] || [ -z "$OUTPUT_PRESET" ]; then
    exit 0
fi

for INPUT in "$@"; do
    if [ ! -f "$INPUT" ]; then
        record_failure "$INPUT" "not a readable file"
        continue
    fi

    OUTPUT=$(unique_output_path "$INPUT" "$BORDER" "$OUTPUT_PRESET")
    DIRECTORY=$(/usr/bin/dirname "$OUTPUT")
    CURRENT_TEMP=$(/usr/bin/mktemp "$DIRECTORY/.borderme.XXXXXX")
    if [ -z "$CURRENT_TEMP" ]; then
        record_failure "$INPUT" "cannot create a file in the source folder"
        continue
    fi

    ERROR_FILE=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/borderme-error.XXXXXX")
    if "$ENGINE" "$INPUT" "$CURRENT_TEMP" "$BORDER" "$OUTPUT_PRESET" 2>"$ERROR_FILE"; then
        if /bin/mv "$CURRENT_TEMP" "$OUTPUT"; then
            CURRENT_TEMP=""
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            /bin/echo "$OUTPUT"
        else
            record_failure "$INPUT" "cannot move the finished image into place"
        fi
    else
        REASON=$(/usr/bin/head -n 1 "$ERROR_FILE" | /usr/bin/tr '\n' ' ')
        if [ -z "$REASON" ]; then
            REASON="image processing failed"
        fi
        record_failure "$INPUT" "$REASON"
    fi
    /bin/rm -f "$ERROR_FILE"

    if [ -n "$CURRENT_TEMP" ] && [ -e "$CURRENT_TEMP" ]; then
        /bin/rm -f "$CURRENT_TEMP"
    fi
    CURRENT_TEMP=""
done

if [ "$SUCCESS_COUNT" -gt 0 ]; then
    if [ "$SUCCESS_COUNT" -eq 1 ]; then
        MESSAGE="Created 1 bordered image."
    else
        MESSAGE="Created $SUCCESS_COUNT bordered images."
    fi
    if [ "$FAILURE_COUNT" -gt 0 ]; then
        MESSAGE="$MESSAGE Skipped $FAILURE_COUNT."
    fi
    show_notification "$MESSAGE"
fi

if [ "$FAILURE_COUNT" -gt 0 ]; then
    if [ "$FAILURE_COUNT" -gt 8 ]; then
        REMAINING=$((FAILURE_COUNT - 8))
        FAILURE_DETAILS="$FAILURE_DETAILS
...and $REMAINING more."
    fi
    show_alert "BorderMe skipped $FAILURE_COUNT file(s):

$FAILURE_DETAILS"
fi

if [ "$SUCCESS_COUNT" -eq 0 ]; then
    exit 1
fi

exit 0
