#!/bin/bash
# TODO: Get the workflow running for tag pushes.
# The only major thing remaining is that the `gh release view` fails because the workflow dispatches faster than the
# publishing of the release allows it to be visible from the GH API. So this workflow needs to be run again in GH GUI
# for it to succeed.
# TODO: Is `prURL` also a tag URL?
# Gutenberg Mobile AKA "GBM".
# WordPress-Android AKA "WPA".
# GitHub AKA "GH".

help() {
  echo "Creates a WordPress-Android (WPA) PR containing changes from Gutenberg Mobile (GBM)."
  echo "The GBM changes can be from a GBM PR or Tag."
  echo
  echo "Syntax: script [--help|--pr|--tag|--token]"
  echo
  echo "--help   Print this Help."
  echo "--pr     GBM PR, e.g., '1337'. (This is REQUIRED if '--tag' is omitted.)"
  echo "--tag    GBM Tag, e.g., 'v1.68.0'. (This is REQUIRED if '--pr' is omitted.)"
  echo "--token  GH Token, e.g., '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'. (This is OPTIONAL if you are logged into 'gh'. However, different tokens may be used for different permissions.)"
  echo
}

abort() {
  printf "%s" "$1"
  exit 1
}

for i in "$@"; do
  case $i in
    --help)
      help
      exit 0
      ;;
    --token=*)
      GITHUB_TOKEN="${i#*=}"
      shift
      ;;
    --pr=*)
      GBM_PR="${i#*=}"
      shift
      ;;
    --tag=*)
      GBM_TAG="${i#*=}"
      shift
      ;;
    *)
      ;;
  esac
done

command -v gh >/dev/null || \
abort "Error: Please 'brew install gh'."

if [ -z "$GITHUB_TOKEN" ]
then
  gh auth status >/dev/null 2>&1 || \
  abort "Error: Please 'gh auth login' to authenticate with GH, or provide a '--token'."
fi

if [ -n "$GBM_PR" ]
then
  GBM_RESPONSE=$(gh pr view "$GBM_PR" \
                  --repo 'https://github.com/wordpress-mobile/gutenberg-mobile' \
                  --json 'url,number,commits' \
                  --jq '.url,.number,.commits[-1].oid')
elif [ -n "$GBM_TAG" ]
then
  GBM_RESPONSE=$(gh release view "$GBM_TAG" \
                  --repo 'https://github.com/wordpress-mobile/gutenberg-mobile' \
                  --json 'url,tagName' \
                  --jq '.url,.tagName')
else
  # Get the PR number from the current branch.
  GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  echo "Creating a Android Sync PR based on the $GIT_BRANCH branch"

  GBM_RESPONSE_PR=$(gh pr list \
                  --head "$GIT_BRANCH" \
                  --repo 'https://github.com/wordpress-mobile/gutenberg-mobile' \
                  --json 'number' \
                  --jq '')
  GBM_PR=${GBM_RESPONSE_PR//[!0-9]/}
  echo ""

  if [ -n "$GBM_PR" ]
  then
    GBM_RESPONSE=$(gh pr view "$GBM_PR" \
                    --repo 'https://github.com/wordpress-mobile/gutenberg-mobile' \
                    --json 'url,number,commits' \
                    --jq '.url,.number,.commits[-1].oid')
  else
    abort "Create a PR first before trying to submit create a sync WordPress Android PR."
  fi
fi

GBM_METADATA=()
while IFS= read -r LINE; do
  GBM_METADATA+=("$LINE")
done <<< "$GBM_RESPONSE"

GBM_URL="${GBM_METADATA[0]}"
WPA_PR_TITLE="Gutenberg Mobile $GBM_URL"

if [ -n "$GBM_PR" ]
then
  GBM_VERSION="${GBM_METADATA[1]}-${GBM_METADATA[2]}"
elif [ -n "$GBM_TAG" ]
then
  GBM_VERSION="${GBM_METADATA[1]}"
else
  abort "GBM PR OR Tag is REQUIRED to be provided with '--pr' or '--tag'."
fi

if [ -n "$GBM_URL" ]
then
  echo "Hello! I'm about to create a WPA PR synchronized with your GBM changes."
  echo "WPA PR Title: '$WPA_PR_TITLE'"
  echo "GBM Version: '$GBM_VERSION'"
  echo "GBM URL: '$GBM_URL'"
  gh workflow run --repo=WordPress-mobile/WordPress-Android automated-version-update-pr.yml \
                  --raw-field title="$WPA_PR_TITLE" \
                  --raw-field gutenbergMobileVersion="$GBM_VERSION" \
                  --raw-field prURL="$GBM_URL"
else
  abort "GBM URL not found with the provided '--pr' or '--tag'."
fi
