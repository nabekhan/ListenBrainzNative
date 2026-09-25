#!/bin/zsh

set -euo pipefail

mode="${1:-check}"
case "$mode" in
    check | sync) ;;
    *)
        print -u2 "Usage: scripts/localizations.sh [check|sync]"
        exit 64
        ;;
esac

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
catalog="$repository_root/App/Resources/Localizable.xcstrings"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/brainz-localizations.XXXXXX")"
derived_data="$temporary_root/DerivedData"

cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

cd "$repository_root"

if ! command -v jq >/dev/null 2>&1; then
    print -u2 "jq is required. Run through Nix with: nix shell nixpkgs#jq -c scripts/localizations.sh $mode"
    exit 69
fi

make_source_copy_editable() {
    local destination="$1"
    local normalized="$temporary_root/normalized.xcstrings"
    jq '
        .strings |= with_entries(
            .key as $key
            | if $key != "" and (.value.localizations.en? == null) then
                .value.localizations.en = {
                    "stringUnit": {
                        "state": "translated",
                        "value": $key
                    }
                }
            else
                .
            end
        )
    ' "$destination" > "$normalized"
    cp "$normalized" "$destination"
}

validate_catalog() {
    local candidate_catalog="$1"
    jq -e '
        .sourceLanguage == "en"
        and (.strings | type == "object")
        and (.strings | has("") | not)
        and (
            .strings
            | to_entries
            | all(.value.localizations.en.stringUnit.value | type == "string")
        )
    ' "$candidate_catalog" >/dev/null
}

typeset -a catalogs
while IFS= read -r -d '' file; do
    catalogs+=("$file")
done < <(find App -type f -name '*.xcstrings' -print0)

if (( ${#catalogs[@]} != 1 )) || [[ "${catalogs[1]:-}" != "App/Resources/Localizable.xcstrings" ]]; then
    print -u2 "Expected exactly one app string catalog at App/Resources/Localizable.xcstrings."
    exit 1
fi

xcodebuild \
    -project ListenBrainzNative.xcodeproj \
    -scheme ListenBrainzNative \
    -configuration Release \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    build -quiet

typeset -a stringsdata_arguments
while IFS= read -r -d '' file; do
    stringsdata_arguments+=(--stringsdata "$file")
done < <(
    find "$derived_data/Build/Intermediates.noindex" \
        -type f \
        -path '*/ListenBrainzNative.build/Release-iphonesimulator/ListenBrainzNative.build/Objects-normal/*/*.stringsdata' \
        -print0
)

if (( ${#stringsdata_arguments[@]} == 0 )); then
    print -u2 "The Release build produced no app localization metadata."
    exit 1
fi

if [[ "$mode" == "sync" ]]; then
    xcrun xcstringstool sync "$catalog" "${stringsdata_arguments[@]}"
    make_source_copy_editable "$catalog"
    validate_catalog "$catalog"
    count="$(jq '.strings | length' "$catalog")"
    print "Synchronized $count production localization keys in ${catalog#$repository_root/}."
    exit 0
fi

candidate="$temporary_root/Localizable.xcstrings"
cp "$catalog" "$candidate"
xcrun xcstringstool sync "$candidate" "${stringsdata_arguments[@]}"
make_source_copy_editable "$candidate"
validate_catalog "$candidate"

if ! cmp -s "$catalog" "$candidate"; then
    source_keys="$temporary_root/source.keys"
    release_keys="$temporary_root/release.keys"
    jq -r '.strings | keys[]' "$catalog" | LC_ALL=C sort -u > "$source_keys"
    jq -r '.strings | keys[]' "$candidate" | LC_ALL=C sort -u > "$release_keys"

    print -u2 "Localizable.xcstrings is out of sync with the production Swift sources."
    missing_keys="$(comm -23 "$release_keys" "$source_keys")"
    stale_keys="$(comm -13 "$release_keys" "$source_keys")"
    if [[ -n "${missing_keys:-}" ]]; then
        print -u2 "\nMissing keys:"
        print -u2 -- "$missing_keys"
    fi
    if [[ -n "${stale_keys:-}" ]]; then
        print -u2 "\nStale non-production keys:"
        print -u2 -- "$stale_keys"
    fi
    print -u2 "\nRun scripts/localizations.sh sync and review the catalog diff."
    exit 1
fi

count="$(jq '.strings | length' "$catalog")"
print "Localizable.xcstrings matches $count production localization keys."
