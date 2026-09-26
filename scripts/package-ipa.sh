#!/bin/zsh

emulate -LR zsh
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

usage() {
    print "Usage: scripts/package-ipa.sh [OUTPUT.ipa]"
    print ""
    print "Build and validate an unsigned, re-signable Brainz IPA."
    print "The IPA is not directly installable; a compatible signer must sign it first."
}

fail() {
    print -u2 "Error: $1"
    exit 1
}

case "$#" in
    0) requested_output="" ;;
    1)
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            *) requested_output="$1" ;;
        esac
        ;;
    *)
        usage >&2
        exit 64
        ;;
esac

invocation_directory="$PWD"
script_directory="${0:A:h}"
repository_root="${script_directory:h}"
source_manifest="$repository_root/App/Resources/PrivacyInfo.xcprivacy"
publication_root=""
temporary_root=""

if [[ -n "$requested_output" ]]; then
    [[ "$requested_output" == *.ipa ]] || fail "The output path must end in .ipa."
    if [[ "$requested_output" == /* ]]; then
        output_path="$requested_output"
    else
        output_path="$invocation_directory/$requested_output"
    fi
    [[ ! -e "$output_path" && ! -L "$output_path" ]] \
        || fail "The output already exists: $output_path"
else
    output_path=""
fi

cleanup() {
    if [[ -n "$publication_root" && -d "$publication_root" ]]; then
        /usr/bin/find "$publication_root" -depth -delete
        [[ ! -d "$publication_root" ]] || /bin/rmdir "$publication_root"
    fi
    if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
        /usr/bin/find "$temporary_root" -depth -delete
        [[ ! -d "$temporary_root" ]] || /bin/rmdir "$temporary_root"
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

required_commands=(
    /bin/cp
    /bin/link
    /bin/mkdir
    /bin/rmdir
    /usr/bin/awk
    /usr/bin/cmp
    /usr/bin/codesign
    /usr/bin/ditto
    /usr/bin/file
    /usr/bin/find
    /usr/bin/grep
    /usr/bin/lipo
    /usr/bin/mktemp
    /usr/bin/plutil
    /usr/bin/shasum
    /usr/bin/sort
    /usr/bin/stat
    /usr/bin/touch
    /usr/bin/unzip
    /usr/bin/zip
    /usr/bin/xcodebuild
    /usr/libexec/PlistBuddy
)
for required_command in "${required_commands[@]}"; do
    [[ -x "$required_command" ]] || fail "Required tool is unavailable: $required_command"
done
[[ -f "$source_manifest" ]] || fail "The source privacy manifest is missing."

temporary_root="$(/usr/bin/mktemp -d /private/tmp/brainz-ipa.XXXXXX)"
derived_data_path="$temporary_root/DerivedData"
archive_path="$temporary_root/Brainz.xcarchive"

cd "$repository_root"
print "Building the unsigned Release archive…"
/usr/bin/xcodebuild \
    -project ListenBrainzNative.xcodeproj \
    -scheme ListenBrainzNative \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data_path" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=- \
    archive \
    -quiet

app_path="$archive_path/Products/Applications/Brainz.app"
info_plist="$app_path/Info.plist"
[[ -d "$app_path" ]] || fail "The archive does not contain Products/Applications/Brainz.app."
[[ -f "$info_plist" ]] || fail "The archived app is missing Info.plist."
/usr/bin/plutil -lint "$info_plist" >/dev/null || fail "The archived Info.plist is invalid."

read_plist_value() {
    local key="$1"
    local value
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$info_plist" 2>/dev/null)" \
        || fail "The archived Info.plist is missing $key."
    [[ -n "$value" ]] || fail "The archived Info.plist has an empty $key."
    print -r -- "$value"
}

bundle_identifier="$(read_plist_value CFBundleIdentifier)"
marketing_version="$(read_plist_value CFBundleShortVersionString)"
build_number="$(read_plist_value CFBundleVersion)"
executable_name="$(read_plist_value CFBundleExecutable)"
[[ "$executable_name" == "Brainz" ]] || fail "The archived executable is $executable_name, not Brainz."

binary_path="$app_path/$executable_name"
[[ -x "$binary_path" ]] || fail "The archived Brainz executable is missing or not executable."
architectures="$(/usr/bin/lipo -archs "$binary_path")" \
    || fail "The archived Brainz executable is not a valid Mach-O binary."
[[ " $architectures " == *" arm64 "* ]] || fail "The archived executable does not contain arm64."
[[ " $architectures " != *" x86_64 "* && " $architectures " != *" i386 "* ]] \
    || fail "The device archive contains a simulator architecture: $architectures"

[[ -f "$app_path/Assets.car" ]] || fail "The archived app is missing Assets.car."
[[ -f "$app_path/AppIcon60x60@2x.png" ]] || fail "The archived app is missing the 120×120 iPhone icon."
[[ -f "$app_path/AppIcon76x76@2x~ipad.png" ]] || fail "The archived app is missing the 152×152 iPad icon."
[[ "$(read_plist_value CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName)" == "AppIcon" ]] \
    || fail "The iPhone primary icon is not AppIcon."
[[ "$(read_plist_value 'CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconName')" == "AppIcon" ]] \
    || fail "The iPad primary icon is not AppIcon."
/usr/libexec/PlistBuddy -c "Print :UILaunchScreen" "$info_plist" >/dev/null 2>&1 \
    || fail "The archived app is missing its generated launch-screen declaration."

bundled_manifest="$app_path/PrivacyInfo.xcprivacy"
[[ -f "$bundled_manifest" ]] || fail "The archived app is missing PrivacyInfo.xcprivacy."
/usr/bin/plutil -lint "$bundled_manifest" >/dev/null || fail "The bundled privacy manifest is invalid."
source_manifest_hash="$(/usr/bin/shasum -a 256 "$source_manifest" | /usr/bin/awk '{print $1}')"
bundled_manifest_hash="$(/usr/bin/shasum -a 256 "$bundled_manifest" | /usr/bin/awk '{print $1}')"
[[ "$source_manifest_hash" == "$bundled_manifest_hash" ]] \
    || fail "The bundled privacy manifest does not match the reviewed source manifest."

if [[ -n "$(/usr/bin/find "$app_path" -name embedded.mobileprovision -print -quit)" ]]; then
    fail "The unsigned payload unexpectedly contains a provisioning profile."
fi
if [[ -n "$(/usr/bin/find "$app_path" -type d -name _CodeSignature -print -quit)" ]]; then
    fail "The unsigned payload unexpectedly contains a code-signature directory."
fi
if [[ -n "$(/usr/bin/find "$app_path" -type l -print -quit)" ]]; then
    fail "The unsigned payload unexpectedly contains a symbolic link."
fi

assert_unsigned_code_object() {
    local candidate="$1"
    local signing_description
    if signing_description="$(/usr/bin/codesign -dv --verbose=4 "$candidate" 2>&1)"; then
        fail "The payload contains signed code: ${candidate#$app_path/}"
    fi
    [[ "$signing_description" == *"code object is not signed at all"* ]] \
        || fail "The unsigned state could not be verified for ${candidate#$app_path/}: $signing_description"
}

assert_unsigned_code_object "$app_path"
integer mach_o_count=0
while IFS= read -r -d '' candidate; do
    if [[ "$(/usr/bin/file -b "$candidate")" == *"Mach-O"* ]]; then
        (( mach_o_count += 1 ))
        assert_unsigned_code_object "$candidate"
    fi
done < <(/usr/bin/find "$app_path" -type f -print0)
(( mach_o_count > 0 )) || fail "The archived app contains no Mach-O code object."

staging_root="$temporary_root/staging"
/bin/mkdir -p "$staging_root/Payload"
/usr/bin/ditto \
    --norsrc \
    --noextattr \
    --noqtn \
    --noacl \
    --nopersistRootless \
    "$app_path" \
    "$staging_root/Payload/Brainz.app"

while IFS= read -r -d '' staged_path; do
    /usr/bin/touch -h -t 198001010000 "$staged_path"
done < <(/usr/bin/find "$staging_root/Payload" -print0)

package_payload() {
    local destination="$1"
    local input_list="$temporary_root/zip-inputs.txt"
    (
        cd "$staging_root"
        LC_ALL=C /usr/bin/find Payload -print | LC_ALL=C /usr/bin/sort > "$input_list"
        /usr/bin/zip -X -q "$destination" -@ < "$input_list"
    )
    /usr/bin/unzip -tqq "$destination" \
        || fail "The packaged IPA failed its ZIP integrity check."
}

validate_payload_layout() {
    local candidate="$1"
    local listing invalid_entries
    listing="$(/usr/bin/unzip -Z1 "$candidate")"
    invalid_entries="$(
        print -r -- "$listing" \
            | /usr/bin/awk '$0 != "Payload/" && $0 != "Payload/Brainz.app/" && index($0, "Payload/Brainz.app/") != 1 { print }'
    )"
    [[ -z "$invalid_entries" ]] \
        || fail "The IPA contains entries outside Payload/Brainz.app: $invalid_entries"
    /usr/bin/grep -Fxq "Payload/Brainz.app/Brainz" <<< "$listing" \
        || fail "The IPA is missing Payload/Brainz.app/Brainz."
    /usr/bin/grep -Fxq "Payload/Brainz.app/Info.plist" <<< "$listing" \
        || fail "The IPA is missing Payload/Brainz.app/Info.plist."
    /usr/bin/grep -Fxq "Payload/Brainz.app/PrivacyInfo.xcprivacy" <<< "$listing" \
        || fail "The IPA is missing Payload/Brainz.app/PrivacyInfo.xcprivacy."
}

first_ipa="$temporary_root/Brainz-first.ipa"
second_ipa="$temporary_root/Brainz-second.ipa"
package_payload "$first_ipa"
package_payload "$second_ipa"
validate_payload_layout "$first_ipa"
/usr/bin/cmp -s "$first_ipa" "$second_ipa" \
    || fail "Packaging the same archive twice produced different IPA bytes."

packaged_manifest_hash="$(
    /usr/bin/unzip -p "$first_ipa" Payload/Brainz.app/PrivacyInfo.xcprivacy \
        | /usr/bin/shasum -a 256 \
        | /usr/bin/awk '{print $1}'
)"
[[ "$packaged_manifest_hash" == "$source_manifest_hash" ]] \
    || fail "The packaged privacy manifest does not match the reviewed source manifest."

if [[ -z "$output_path" ]]; then
    output_path="$repository_root/dist/Brainz-${marketing_version}-${build_number}-unsigned.ipa"
fi
[[ ! -e "$output_path" && ! -L "$output_path" ]] \
    || fail "The output already exists: $output_path"
output_directory="${output_path:h}"
/bin/mkdir -p "$output_directory"
directory_permissions="$(/usr/bin/stat -f '%Sp' "$output_directory")"
if [[ "${directory_permissions[6]}" == "w" || "${directory_permissions[9]}" == "w" ]]; then
    [[ "${directory_permissions[10]}" == "t" || "${directory_permissions[10]}" == "T" ]] \
        || fail "The output directory is writable by other users and does not have sticky-bit protection."
fi
publication_root="$(/usr/bin/mktemp -d "$output_directory/.brainz-ipa-publish.XXXXXX")"
partial_output="$publication_root/artifact.ipa"
/bin/cp "$first_ipa" "$partial_output"
/bin/link "$partial_output" "$output_path" \
    || fail "The output appeared while packaging; no existing file was replaced."
/usr/bin/find "$publication_root" -depth -delete
publication_root=""

artifact_hash="$(/usr/bin/shasum -a 256 "$output_path" | /usr/bin/awk '{print $1}')"
artifact_size="$(/usr/bin/stat -f '%z' "$output_path")"

print ""
print "Created an unsigned, re-signable IPA:"
print "  $output_path"
print "  Bundle: $bundle_identifier"
print "  Version: $marketing_version ($build_number)"
print "  Architecture: $architectures"
print "  Size: $artifact_size bytes"
print "  SHA-256: $artifact_hash"
print ""
print "This IPA is not directly installable. Re-sign it with a compatible provisioning identity before sideloading."
