#!/bin/bash

# Exit if any command fails
set -e

function warn_missing_tag_commit() {
    RED="\033[0;31m"
    NO_COLOR="\033[0m"
    PODSPEC_HAS_TAG_OR_COMMIT=$(jq '.source | has("tag") or has("commit")' "$DEST/$pod.podspec.json")
    # If the source points to an HTTP endpoint and SHA, we consider it versioned
    PODSPEC_HAS_HTTP_AND_SHA=$(jq '.source | has("http") and (has("sha256") or has("sha1"))' "$DEST/$pod.podspec.json")

    if [[ $PODSPEC_HAS_TAG_OR_COMMIT == "false" && $PODSPEC_HAS_HTTP_AND_SHA == "false" ]]; then
        printf "${RED}WARNING! $pod.podspec doesn't have a 'tag' or 'commit' field, or doesn't point to a SHA verified file. Either modify this script to add a patch during the podspec generation or modify the original $pod.podspec in the source repo.${NO_COLOR}\n"
        exit 1
    fi
}

# Change to the expected directory.
pushd "$( dirname "$0" )" > /dev/null
popd > /dev/null
WD=$(pwd)
echo "Working directory: $WD"

# Check for cocoapods & jq
command -v pod > /dev/null || ( echo Cocoapods is required to generate podspecs; exit 1 )
command -v jq > /dev/null || ( echo jq is required to generate podspecs; exit 1 )

read -r -p "If your node_modules folder isn't up-to-date please run 'npm install' first and re-run the script. Is your node_modules folder up-to-date? [y/N] " PROMPT_RESPONSE
if [[ $PROMPT_RESPONSE != "y" ]]; then
    echo "Please run npm install first and re-run the script."
    exit 1
fi

read -r -p "Enter the commit hash of previous commit. If this is the first-time running this script, enter 0, then commit generated files and re-rerun the script and this time use the previous commit hash: " COMMIT_HASH
if [[ -z "$COMMIT_HASH" ]]; then
    echo "Commit hash cannot be empty."
    exit 1
fi

DEST="${WD}/third-party-podspecs"
read -r -p "Please delete '$DEST' folder manually before continuing. This script will re-generate it. Did you delete it? [y/N] " PROMPT_RESPONSE_2
if [[ $PROMPT_RESPONSE_2 != "y" ]]; then
    echo "Aborting."
    exit 1
fi

mkdir "$DEST"

NODE_MODULES_DIR="gutenberg/node_modules"

# Generate the external (non-RN podspecs)
EXTERNAL_PODSPECS=$(find "$NODE_MODULES_DIR/react-native/third-party-podspecs" \
                         "$NODE_MODULES_DIR/@react-native-community/blur" \
                         "$NODE_MODULES_DIR/@react-native-masked-view/masked-view" \
                         "$NODE_MODULES_DIR/@react-native-community/slider" \
                         "$NODE_MODULES_DIR/@react-native-clipboard/clipboard" \
                         "$NODE_MODULES_DIR/react-native-gesture-handler" \
                         "$NODE_MODULES_DIR/react-native-get-random-values" \
                         "$NODE_MODULES_DIR/react-native-linear-gradient" \
                         "$NODE_MODULES_DIR/react-native-reanimated" \
                         "$NODE_MODULES_DIR/react-native-safe-area" \
                         "$NODE_MODULES_DIR/react-native-safe-area-context" \
                         "$NODE_MODULES_DIR/react-native-screens" \
                         "$NODE_MODULES_DIR/react-native-svg" \
                         "$NODE_MODULES_DIR/react-native-video"\
                         "$NODE_MODULES_DIR/react-native-webview"\
                         "$NODE_MODULES_DIR/react-native-fast-image"\
                          -type f -name "*.podspec" -print)

for podspec in $EXTERNAL_PODSPECS
do
    pod=$(basename "$podspec" .podspec)

    echo "Generating podspec for $pod"
    pod ipc spec "$podspec" > "$DEST/$pod.podspec.json"

    # react-native-blur doesn't have a tag field in it's podspec
    if [[ "$pod" == "react-native-blur" ]]; then
        echo "   ==> Patching $pod podspec"
        TMP_RNBlurPodspec=$(mktemp)
        # The npm version we're using is 3.6.0 because 3.6.1 still isn't on npm https://www.npmjs.com/package/@react-native-community/blur/v/3.6.1
        # And there's no v3.6.0 tag in https://github.com/Kureev/react-native-blur so we depend on v3.6.1 in the podspec
        jq '.source.tag = "v3.6.1" | .version = "3.6.1"' "$DEST/$pod.podspec.json" > "$TMP_RNBlurPodspec"
        mv "$TMP_RNBlurPodspec" "$DEST/$pod.podspec.json"
    fi

    # Add warning to bottom
    TMP_SPEC=$(mktemp)
    jq '. + {"__WARNING!__": "This file is autogenerated by generate-podspecs.sh script. Do not modify manually. Re-run the script if necessary."}' "$DEST/$pod.podspec.json" > "$TMP_SPEC"
    mv "$TMP_SPEC" "$DEST/$pod.podspec.json"

    # As a last step check if podspec has a "tag" or "commit" field in "source"
    warn_missing_tag_commit
done

# Generate the React Native podspecs
# Change to the React Native directory to get relative paths for the RN podspecs
pushd "$NODE_MODULES_DIR/react-native" > /dev/null

RN_DIR="./"
SCRIPTS_PATH="./scripts/"
CODEGEN_REPO_PATH="../packages/react-native-codegen"
CODEGEN_NPM_PATH="../react-native-codegen"
SRCS_DIR=${SRCS_DIR:-$(cd "./Libraries" && pwd)}
RN_VERSION=$(cat ./package.json | grep -m 1 version | sed 's/[^0-9.]//g')

RN_PODSPECS=$(find * -type f -name "*.podspec" -not -name "React-rncore.podspec" -not -path "third-party-podspecs/*" -not -path "*Fabric*" -print)
TMP_DEST=$(mktemp -d)

for podspec in $RN_PODSPECS
do
    pod=$(basename "$podspec" .podspec)
    path=$(dirname "$podspec")

    echo "Generating podspec for $pod with path $path"
    pod ipc spec "$podspec" > "$TMP_DEST/$pod.podspec.json"
    # Removes message [Codegen] Found at the beginning of the file
    sed -i '' -e '/\[Codegen\] Found/d' "$TMP_DEST/$pod.podspec.json"
    cat "$TMP_DEST/$pod.podspec.json" | jq > "$DEST/$pod.podspec.json"

    # Add a "prepare_command" entry to each podspec so that 'pod install' will fetch sources from the correct directory
    # and retains the existing prepare_command if it exists
    prepare_command="TMP_DIR=\$(mktemp -d); mv * \$TMP_DIR; cp -R \"\$TMP_DIR/${path}\"/* ."
    cat "$TMP_DEST/$pod.podspec.json" | jq --arg CMD "$prepare_command" '.prepare_command = "\($CMD) && \(.prepare_command // true)"' > "$DEST/$pod.podspec.json"

    # Add warning to bottom
    TMP_SPEC=$(mktemp)
    jq '. + {"__WARNING!__": "This file is autogenerated by generate-podspecs.sh script. Do not modify manually. Re-run the script if necessary."}' "$DEST/$pod.podspec.json" > "$TMP_SPEC"
    mv "$TMP_SPEC" "$DEST/$pod.podspec.json"

    # As a last step check if podspec has a "tag" or "commit" field in "source"
    warn_missing_tag_commit

    # FBReactNativeSpec needs special treatment because of react-native-codegen code generation
    if [[ "$pod" == "FBReactNativeSpec" ]]; then
        echo "   ==> Patching $pod podspec"
        # First move it to its own folder
        mkdir -p "$DEST/FBReactNativeSpec"
        mv "$DEST/FBReactNativeSpec.podspec.json" "$DEST/FBReactNativeSpec"

        # Then we generate FBReactNativeSpec-generated.mm and FBReactNativeSpec.h files.
        # They are normally generated during compile time using a Script Phase in FBReactNativeSpec added via the `use_react_native_codegen` function.
        # This script is inside node_modules/react-native/scripts folder. Since we don't have the node_modules when compiling WPiOS,
        # we're calling the script here manually to generate these files ahead of time.
        SCHEMA_FILE="$TMP_DEST/schema.json"
        NODE_BINARY="${NODE_BINARY:-$(command -v node || true)}"

        if [ -d "$CODEGEN_REPO_PATH" ]; then
            CODEGEN_PATH=$(cd "$CODEGEN_REPO_PATH" && pwd)
        elif [ -d "$CODEGEN_NPM_PATH" ]; then
            CODEGEN_PATH=$(cd "$CODEGEN_NPM_PATH" && pwd)
        else
            echo "Error: Could not determine react-native-codegen location. Try running 'yarn install' or 'npm install' in your project root." 1>&2
            exit 1
        fi

        if [ ! -d "$CODEGEN_PATH/lib" ]; then
            describe "Building react-native-codegen package"
            bash "$CODEGEN_PATH/scripts/oss/build.sh"
        fi

        # Generate React-Codegen
        # A copy of react_native_pods is done to modify the content within get_react_codegen_spec
        # this enables getting the schema for React-Codegen in runtime by printing the content.
        echo "Generating React-Codegen"
        REACT_NATIVE_PODS_PATH="$SCRIPTS_PATH/react_native_pods.rb"
        REACT_NATIVE_PODS_MODIFIED_PATH="$SCRIPTS_PATH/react_native_pods_modified.rb"
        # Making a temp copy of react_native_pods.rb
        cp $REACT_NATIVE_PODS_PATH $REACT_NATIVE_PODS_MODIFIED_PATH
        # Modify the get_react_codegen_spec method to return the result using print and JSON.pretty
        sed -i '' -e "s/:git => ''/:git => 'https:\/\/github.com\/facebook\/react-native.git', :tag => 'v$RN_VERSION'/" "$REACT_NATIVE_PODS_MODIFIED_PATH"
        sed -i '' -e 's/return spec/print JSON.pretty_generate(spec)/' "$REACT_NATIVE_PODS_MODIFIED_PATH"
        # Run get_react_codegen_spec and generate React-Codegen.podspec.json
        ruby -r "./scripts/react_native_pods_modified.rb" -e "get_react_codegen_spec" > "$DEST/React-Codegen.podspec.json"
        TMP_ReactCodeGenSpec=$(mktemp)
        jq '.source_files = "third-party-podspecs/FBReactNativeSpec/**/*.{c,h,m,mm,cpp}"' "$DEST/React-Codegen.podspec.json" > "$TMP_ReactCodeGenSpec"
        mv "$TMP_ReactCodeGenSpec" "$DEST/React-Codegen.podspec.json"
        # Remove temp copy of react_native_pods.rb
        rm $REACT_NATIVE_PODS_MODIFIED_PATH

        echo "Generating schema from Flow types"
        "$NODE_BINARY" "$CODEGEN_PATH/lib/cli/combine/combine-js-to-schema-cli.js" "$SCHEMA_FILE" "$SRCS_DIR"

        echo "Generating native code from schema (iOS)"
        "$NODE_BINARY" "./scripts/generate-specs-cli.js" -p "ios" -s "$SCHEMA_FILE" -o "$DEST/FBReactNativeSpec"

        # Removing unneeded files
        find "$DEST/FBReactNativeSpec" -type f -not -name "FBReactNativeSpec.podspec.json" -not -name "FBReactNativeSpec-generated.mm" -not -name "FBReactNativeSpec.h" -not -name "FBReactNativeSpec.h" -delete

        # Removing 'script_phases' that shouldn't be needed anymore.
        # Removing 'prepare_command' that includes additional steps to create intermediate folders to keep generated files which won't be needed.
        # Removing 'source.tag' as we'll use a commit hash from gutenberg-mobile instead.
        TMP_FBReactNativeSpec=$(mktemp)
        jq --arg COMMIT_HASH "$COMMIT_HASH" 'del(.script_phases) | del(.prepare_command) | del(.source.tag) | .source.git = "https://github.com/wordpress-mobile/gutenberg-mobile.git" | .source.commit = $COMMIT_HASH | .source.submodules = "true" | .source_files = "third-party-podspecs/FBReactNativeSpec/**/*.{c,h,m,mm,cpp}"' "$DEST/FBReactNativeSpec/FBReactNativeSpec.podspec.json" > "$TMP_FBReactNativeSpec"
        mv "$TMP_FBReactNativeSpec" "$DEST/FBReactNativeSpec/FBReactNativeSpec.podspec.json"
    fi
done
popd > /dev/null

if [[ "$COMMIT_HASH" != "0" ]]; then
    echo 'Updating XCFramework Podfile.lock with these changes'
    pushd ios-xcframework > /dev/null
    bundle exec pod update
    popd > /dev/null
fi
