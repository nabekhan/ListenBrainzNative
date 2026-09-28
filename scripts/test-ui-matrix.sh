#!/bin/zsh

# Run the credential-free UI regression matrix without changing the caller's
# simulator appearance, Dynamic Type, or boot state. The output directory is
# intentionally retained for XCResult/screenshot inspection.
emulate -LR zsh
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

usage() {
    print "Usage: scripts/test-ui-matrix.sh --iphone-udid UDID --ipad-udid UDID [--output-root DIRECTORY]"
    print ""
    print "Runs only deterministic fixture tests protected by the request-denial guard."
    print "The opt-in live MetaBrainz sign-in test is always skipped."
}

fail() {
    print -u2 "Error: $1"
    exit 1
}

iphone_udid=""
ipad_udid=""
requested_output_root=""

while (( $# > 0 )); do
    case "$1" in
        --iphone-udid)
            (( $# >= 2 )) || fail "--iphone-udid requires a simulator UDID."
            iphone_udid="$2"
            shift 2
            ;;
        --ipad-udid)
            (( $# >= 2 )) || fail "--ipad-udid requires a simulator UDID."
            ipad_udid="$2"
            shift 2
            ;;
        --output-root)
            (( $# >= 2 )) || fail "--output-root requires a directory path."
            requested_output_root="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 64
            ;;
    esac
done

[[ -n "$iphone_udid" ]] || fail "An explicit --iphone-udid is required."
[[ -n "$ipad_udid" ]] || fail "An explicit --ipad-udid is required."
[[ "$iphone_udid" != "$ipad_udid" ]] || fail "The iPhone and iPad UDIDs must be different."

required_commands=(
    /bin/mkdir
    /bin/sleep
    /usr/bin/awk
    /usr/bin/grep
    /usr/bin/mktemp
    /usr/bin/xcodebuild
    /usr/bin/xcrun
)
for command_path in "${required_commands[@]}"; do
    [[ -x "$command_path" ]] || fail "Required tool is unavailable: $command_path"
done

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
[[ -f "$repository_root/ListenBrainzNative.xcodeproj/project.pbxproj" ]] \
    || fail "Run XcodeGen first; ListenBrainzNative.xcodeproj is missing."

if [[ -n "$requested_output_root" ]]; then
    if [[ "$requested_output_root" == /* ]]; then
        output_root="$requested_output_root"
    else
        output_root="$PWD/$requested_output_root"
    fi
    [[ ! -e "$output_root" && ! -L "$output_root" ]] \
        || fail "The output root already exists: $output_root"
    /bin/mkdir -p "$output_root"
else
    output_root="$(/usr/bin/mktemp -d /private/tmp/brainz-ui-matrix.XXXXXX)"
fi
output_root="${output_root:A}"
print "UI matrix output root: $output_root"

device_line() {
    /usr/bin/xcrun simctl list devices | /usr/bin/awk -v udid="$1" '
        index($0, "(" udid ")") { print; exit }
    '
}

device_state() {
    local line
    line="$(device_line "$1")"
    [[ -n "$line" ]] || return 1
    if [[ "$line" == *"(Booted)"* ]]; then
        print "Booted"
    elif [[ "$line" == *"(Shutdown)"* ]]; then
        print "Shutdown"
    else
        print "Unavailable"
    fi
}

validate_device() {
    local udid="$1"
    local expected_name="$2"
    local line state
    line="$(device_line "$udid")"
    [[ -n "$line" ]] || fail "Simulator UDID was not found: $udid"
    [[ "$line" == *"$expected_name"* ]] \
        || fail "Simulator $udid is not an $expected_name destination: $line"
    [[ "$line" != *"unavailable"* ]] || fail "Simulator is unavailable: $line"
    state="$(device_state "$udid")" || fail "Could not determine simulator state: $udid"
    [[ "$state" != "Unavailable" ]] || fail "Simulator is not bootable: $line"
}

validate_device "$iphone_udid" "iPhone"
validate_device "$ipad_udid" "iPad"

iphone_initial_state="$(device_state "$iphone_udid")"
ipad_initial_state="$(device_state "$ipad_udid")"
iphone_initial_appearance=""
ipad_initial_appearance=""
iphone_initial_content_size=""
ipad_initial_content_size=""

ui_setting() {
    local udid="$1"
    local setting="$2"
    /usr/bin/xcrun simctl ui "$udid" "$setting" \
        | /usr/bin/awk 'NF { print $1; exit }'
}

verify_setting() {
    local udid="$1"
    local expected_appearance="$2"
    local expected_content_size="$3"
    local actual_appearance=""
    local actual_content_size=""
    integer attempt
    for attempt in {1..20}; do
        actual_appearance="$(ui_setting "$udid" appearance)"
        actual_content_size="$(ui_setting "$udid" content_size)"
        if [[ "$actual_appearance" == "$expected_appearance" \
            && "$actual_content_size" == "$expected_content_size" ]]; then
            return
        fi
        /bin/sleep 0.25
    done
    print -u2 "Error: Simulator $udid UI state is $actual_appearance/$actual_content_size, expected $expected_appearance/$expected_content_size."
    return 1
}

set_and_verify_ui() {
    local udid="$1"
    local appearance="$2"
    local content_size="$3"
    /usr/bin/xcrun simctl ui "$udid" appearance "$appearance"
    /usr/bin/xcrun simctl ui "$udid" content_size "$content_size"
    verify_setting "$udid" "$appearance" "$content_size" \
        || fail "Could not verify the requested simulator UI state."
}

restore_device() {
    local udid="$1"
    local initial_state="$2"
    local appearance="$3"
    local content_size="$4"
    local current_state=""
    local restoration_failed=0

    current_state="$(device_state "$udid")" || {
        print -u2 "Error: Could not read simulator state during restoration: $udid"
        restoration_failed=1
    }

    if [[ -n "$appearance" && -n "$content_size" ]]; then
        if [[ "$current_state" != "Booted" ]]; then
            if /usr/bin/xcrun simctl boot "$udid" >/dev/null 2>&1 \
                && /usr/bin/xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1; then
                current_state="Booted"
            else
                print -u2 "Error: Could not boot simulator to restore UI settings: $udid"
                restoration_failed=1
            fi
        fi

        if [[ "$current_state" == "Booted" ]]; then
            /usr/bin/xcrun simctl ui "$udid" appearance "$appearance" >/dev/null 2>&1 || {
                print -u2 "Error: Could not restore simulator appearance: $udid"
                restoration_failed=1
            }
            /usr/bin/xcrun simctl ui "$udid" content_size "$content_size" >/dev/null 2>&1 || {
                print -u2 "Error: Could not restore simulator content size: $udid"
                restoration_failed=1
            }
            verify_setting "$udid" "$appearance" "$content_size" || restoration_failed=1
        fi
    fi

    if [[ "$initial_state" == "Shutdown" ]]; then
        if [[ "$current_state" == "Booted" ]]; then
            /usr/bin/xcrun simctl shutdown "$udid" >/dev/null 2>&1 || {
                print -u2 "Error: Could not restore simulator shutdown state: $udid"
                restoration_failed=1
            }
        elif [[ "$current_state" != "Shutdown" ]]; then
            print -u2 "Error: Could not confirm restored simulator shutdown state: $udid"
            restoration_failed=1
        fi
    elif [[ "$initial_state" == "Booted" && "$current_state" != "Booted" ]]; then
        if /usr/bin/xcrun simctl boot "$udid" >/dev/null 2>&1 \
            && /usr/bin/xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1; then
            current_state="Booted"
        else
            print -u2 "Error: Could not restore simulator booted state: $udid"
            restoration_failed=1
        fi
    fi

    return "$restoration_failed"
}

cleanup() {
    local original_status=$?
    local restoration_failed=0
    trap - EXIT HUP INT TERM

    restore_device "$iphone_udid" "$iphone_initial_state" "$iphone_initial_appearance" "$iphone_initial_content_size" \
        || restoration_failed=1
    restore_device "$ipad_udid" "$ipad_initial_state" "$ipad_initial_appearance" "$ipad_initial_content_size" \
        || restoration_failed=1
    print "UI matrix output retained: $output_root"

    if (( restoration_failed != 0 )); then
        print -u2 "Error: One or more simulator settings or boot states could not be restored."
        (( original_status != 0 )) || original_status=1
    fi
    exit "$original_status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

boot_and_wait() {
    local udid="$1"
    local state="$2"
    if [[ "$state" == "Shutdown" ]]; then
        /usr/bin/xcrun simctl boot "$udid"
    fi
    /usr/bin/xcrun simctl bootstatus "$udid" -b
}

boot_and_wait "$iphone_udid" "$iphone_initial_state"
boot_and_wait "$ipad_udid" "$ipad_initial_state"

iphone_initial_appearance="$(ui_setting "$iphone_udid" appearance)"
ipad_initial_appearance="$(ui_setting "$ipad_udid" appearance)"
iphone_initial_content_size="$(ui_setting "$iphone_udid" content_size)"
ipad_initial_content_size="$(ui_setting "$ipad_udid" content_size)"

set_and_verify_ui "$iphone_udid" light large
set_and_verify_ui "$ipad_udid" light large

destination_for() {
    print "platform=iOS Simulator,id=$1"
}

run_tests() {
    local destination="$1"
    local result_bundle="$2"
    local matrix_device="$3"
    local matrix_variant="$4"
    shift 4
    BRAINZ_UI_MATRIX_DEVICE="$matrix_device" \
        BRAINZ_UI_MATRIX_VARIANT="$matrix_variant" \
        /usr/bin/xcodebuild -quiet test-without-building \
        -project ListenBrainzNative.xcodeproj \
        -scheme ListenBrainzNative \
        -destination "$destination" \
        -derivedDataPath "$output_root/DerivedData" \
        -resultBundlePath "$result_bundle" \
        "$@"
}

cd "$repository_root"
iphone_destination="$(destination_for "$iphone_udid")"
ipad_destination="$(destination_for "$ipad_udid")"

print "Building the UI test products once for the explicit iPhone destination…"
/usr/bin/xcodebuild -quiet build-for-testing \
    -project ListenBrainzNative.xcodeproj \
    -scheme ListenBrainzNative \
    -destination "$iphone_destination" \
    -derivedDataPath "$output_root/DerivedData"

ui_test_class="ListenBrainzNativeUITests/ReleaseLayoutUITests"
live_auth_test="$ui_test_class/testLiveWebSignInReachesOfficialMetaBrainzPage"

print "Running the full deterministic iPhone fixture suite…"
run_tests "$iphone_destination" "$output_root/iphone-fixtures.xcresult" iphone baseline \
    "-only-testing:$ui_test_class" \
    "-skip-testing:$live_auth_test"

print "Running the established responsive/RTL/pseudo-localization iPad fixtures…"
run_tests "$ipad_destination" "$output_root/ipad-responsive.xcresult" ipad responsive \
    "-only-testing:$ui_test_class/testHomeFixtureUsesRegularWidthInPortrait" \
    "-only-testing:$ui_test_class/testHomeFixtureAdaptsToLandscape" \
    "-only-testing:$ui_test_class/testHistoryControlsFollowRightToLeftLayout" \
    "-only-testing:$ui_test_class/testFeedFixtureSurvivesRightToLeftLayout" \
    "-only-testing:$ui_test_class/testProfilePlaylistsFixtureSurvivesRightToLeftLayout" \
    "-only-testing:$ui_test_class/testHomeFixtureSurvivesExpandedPseudoLocalization"

set_and_verify_ui "$iphone_udid" dark accessibility-extra-extra-extra-large
print "Running the focused dark, maximum-Dynamic-Type iPhone fixtures…"
run_tests "$iphone_destination" "$output_root/iphone-dark-accessibility.xcresult" iphone dark-accessibility \
    "-only-testing:$ui_test_class/testHomeFixtureExposesMetricSemantics" \
    "-only-testing:$ui_test_class/testCommunityChartsPageOnlyAfterExplicitLoadMoreAction" \
    "-only-testing:$ui_test_class/testFeedbackLibraryLoadsOnlyTheSelectedRatingAndPagesExplicitly" \
    "-only-testing:$ui_test_class/testYearInMusicFixtureSurvivesExpandedPseudoLocalization"

print "UI simulator matrix completed successfully. Inspect: $output_root"
