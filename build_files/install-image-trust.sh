#!/usr/bin/bash

set -euo pipefail

if [[ "$#" -lt 1 ]]; then
    echo "Usage: install-image-trust.sh ghcr.io/owner/image [ghcr.io/owner/image ...]"
    exit 1
fi

POLICY="/etc/containers/policy.json"
KEY="/usr/lib/pki/containers/iegorch86.pub"

echo "Installing custom image signature trust"

if [[ ! -f /ctx/cosign.pub ]]; then
    echo "ERROR: /ctx/cosign.pub is missing."
    exit 1
fi

if [[ ! -f "${POLICY}" ]]; then
    echo "ERROR: ${POLICY} is missing."
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required to safely modify ${POLICY}."
    exit 1
fi

install -Dm0644 /ctx/cosign.pub "${KEY}"

working_policy="$(mktemp)"
next_policy="$(mktemp)"
trap 'rm -f "${working_policy}" "${next_policy}"' EXIT

cp "${POLICY}" "${working_policy}"

for image_repo in "$@"; do
    echo "Adding sigstore trust for ${image_repo}"

    jq \
        --arg repo "${image_repo}" \
        --arg key "${KEY}" \
        '
        .transports |= (. // {}) |
        .transports.docker |= (. // {}) |
        .transports.docker[$repo] = [
            {
                "type": "sigstoreSigned",
                "keyPath": $key,
                "signedIdentity": {
                    "type": "matchRepository"
                }
            }
        ]
        ' \
        "${working_policy}" > "${next_policy}"

    jq empty "${next_policy}"
    mv "${next_policy}" "${working_policy}"
    next_policy="$(mktemp)"
done

install -m0644 "${working_policy}" "${POLICY}"

echo "Container signature trust installed successfully."
