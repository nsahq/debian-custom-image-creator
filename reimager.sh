#!/bin/bash

set -o pipefail
set -o nounset

# ===================================================================== #
#  title:            reimager                                           #
#  description:      Custom Debian ISO image creator                    #
#  author:           Jonas Werme <jonas.werme@hoofbite.com>             #
#  date:             2022-07-22                                         #
# ===================================================================== #

VERSION="1.1.0"

DIR=$(
    cd "$(dirname "$0")"
    pwd -P
)
CHECKSUM_DIR="cache"
PAYLOAD_DIR="payload"
IMAGE_DIR="cache"
PARTS_DIR="parts"
OUT_DIR="out"

display_help() {
    echo "Usage: $(basename ${BASH_SOURCE[0]}) [options]"
    echo ""
    echo "    -a STR    Architecture. <arm64|amd64> Default: amd64"
    echo "    -l STR    ISO volume label."
    echo "    -n STR    Append string to ISO name (before .iso)."
    echo "    -h        Print this help message."
    echo "    -r STR    Choose release. <stable|testing> Default: stable"
    echo "    -v        Show version and exit."
    echo ""
}

display_version() {
    echo "$(basename ${BASH_SOURCE[0]}) v${VERSION}"
    echo "Copyright (C) 2022 Jonas Werme, NSAHQ"
    echo "MIT License <https://github.com/nsahq/debian-custom-image-creator/blob/main/LICENSE>"
    echo "This is free software: you are free to change and redistribute it."
    echo "There is NO WARRANTY."
}

get() {
    wget -c -nv --show-progress --timeout=60 -O "${2}" "${1}" || return 1
    return 0
}

download_file() {
    local remote="${1}"
    local dest="${2}"
    local desc="${3:-file}"

    if [ ! -f "${dest}" ]; then
        echo "Downloading ${desc}... "
        get "${remote}" "${dest}" || (echo "Download failed" && rm "${dest}" &>/dev/null && exit 1)
    else
        echo "Found local ${desc}... download skipped."
    fi
    return 0
}

validate_checksum() {
    local computed_sha="${1}"
    local true_sha="${2}"

    if [ ! "${computed_sha}" = "${true_sha}" ]; then
        echo "Checksum mismatch"
        echo "Value is:  ${computed_sha}"
        echo "Should be: ${true_sha}"
        return 1
    fi
    return 0
}

validate_download() {
    # Get checksum values
    local filter="${3}"
    local download_sha=$(sha256sum "${1}" | awk '{print $1}')
    local true_download_sha=$(grep "${filter}" "${2}" | awk '{print $1}')
    local desc="${4:-file}"

    # Validate checksum
    echo -n "Validating ${desc} checksum... "
    (validate_checksum "${download_sha}" "${true_download_sha}" && echo "ok") || return 2
    return 0
}

clean_parts() {
    # Clear leftovers
    if (($(ls "${PARTS_DIR}" | wc -l))); then
        echo -n "Removing parts... "
        (chmod -R +w "${PARTS_DIR}"/*) || (echo "failed" && exit 3)
        (rm -rf "${PARTS_DIR:?}" && echo "ok") || (echo "failed" && exit 3)
    fi
}

get_source() {
    local checksum_remote="${1}"
    local checksum_dest="${2}"
    local file_remote="${3}"
    local file_dest="${4}"
    local filter="${5}"
    local desc="${6:-file}"

    # Get checksum file
    download_file "${checksum_remote}" "${checksum_dest}" "${desc} checksum"

    # Download needed file
    download_file "${file_remote}" "${file_dest}" "${desc}"

    # Validate recently downloaded file
    validate_download "${file_dest}" "${checksum_dest}" "${filter}" "${desc}"
    if (($?)); then
        rm "${file_dest}" &>/dev/null || return 3

        echo "Re-downloading ${desc}"
        download_file "${file_remote}" "${file_dest}" "${desc}"

        validate_download "${file_dest}" "${checksum_dest}" "${filter}" "${desc}"
        if (($?)); then
            rm "${file_dest}" &>/dev/null
            rm "${checksum_dest}" &>/dev/null
            echo "Failed download, exiting"
            clean_parts
            exit 1
        fi
    fi
}

run_command() {
    echo -n "${2}..."
    if eval "${1}"; then
        echo "ok"
    else
        echo "failed"
        echo "Error detected, aborting script"
        exit 1
    fi
}

main() {
    [ $(which xorriso) ] || {
        echo "xorriso required, please install and try again"
        exit 1
    }

    # Set the correct base image
    if [ ${DEBIAN_RELEASE} = "stable" ]; then
        DEBIAN_LINK="http://cdimage.debian.org/debian-cd/current/${ARCH}/iso-cd"
        [[ $(curl -s "${DEBIAN_LINK}/") =~ debian-([[:digit:]]+.[[:digit:]]+.[[:digit:]]+)-${ARCH}-netinst ]] && DEBIAN_VERSION=${BASH_REMATCH[1]}
    else
        DEBIAN_LINK="http://cdimage.debian.org/cdimage/weekly-builds/${ARCH}/iso-cd"
        DEBIAN_VERSION="testing"
    fi
    echo "Current Debian Version: ${DEBIAN_VERSION}"
    DEBIAN_IMAGE="debian-${DEBIAN_VERSION}-${ARCH}-netinst"

    # Use the latest firmware package for the release
    FIRMWARE_LINK="http://cdimage.debian.org/cdimage/unofficial/non-free/firmware/${DEBIAN_RELEASE}/current"

    run_command 'cd "${DIR}"' \
        "Set script directory to ${DIR}"

    # Ensure base directories exists
    run_command 'mkdir -p "${PAYLOAD_DIR}" "${IMAGE_DIR}" "${CHECKSUM_DIR}" "${PARTS_DIR}" "${OUT_DIR}"' \
        "Ensure base directories are present"

    clean_parts

    # Get debian ISO and checksum validate
    local image_checksum_remote="${DEBIAN_LINK}/SHA256SUMS"
    local image_checksum_dest="${CHECKSUM_DIR}/image-${DEBIAN_VERSION}-SHA256SUMS"
    local image_remote="${DEBIAN_LINK}/${DEBIAN_IMAGE}.iso"
    local image_dest="${IMAGE_DIR}/${DEBIAN_IMAGE}.iso"

    get_source "${image_checksum_remote}" "${image_checksum_dest}" "${image_remote}" "${image_dest}" "${DEBIAN_IMAGE}" "Debian ISO"

    # Get firmware and checksum validate
    local firmware_checksum_remote="${FIRMWARE_LINK}/SHA256SUMS"
    local firmware_checksum_dest="${CHECKSUM_DIR}/firmware-SHA256SUMS"
    local firmware_remote="${FIRMWARE_LINK}/firmware.cpio.gz"
    local firmware_dest="${IMAGE_DIR}/firmware.cpio.gz"

    get_source "${firmware_checksum_remote}" "${firmware_checksum_dest}" "${firmware_remote}" "${firmware_dest}" "firmware.cpio.gz" "firmware"

    # Create bootsector binary for hybrid ISO
    run_command 'dd if="${image_dest}" of="${PARTS_DIR}/isohdpfx.bin" bs=512 count=1 &>/dev/null' \
        "Create isohdpfx.bin from ISO (512 first bytes)"

    # Unpack ISO
    run_command 'xorriso -osirrox on -indev "${IMAGE_DIR}/${DEBIAN_IMAGE}.iso" -extract / "${PARTS_DIR}/${DEBIAN_IMAGE}" &>/dev/null' \
        "Unpacking Debian ISO"

    run_command 'chmod -R u+w "${PARTS_DIR}/${DEBIAN_IMAGE}" &>/dev/null' \
        "Granting write permission on Debian image directory"

    if [ "${PAYLOAD}" != "" ]; then
        run_command 'cp -Raf "${PAYLOAD_DIR}/${PAYLOAD}/." "${PARTS_DIR}/${DEBIAN_IMAGE}/"' \
            "Copying payload from ${PAYLOAD_DIR}/${PAYLOAD} to image directory"
    fi

    # Create new initrd.gz
    run_command 'cp "${PARTS_DIR}/${DEBIAN_IMAGE}/install.amd/initrd.gz" "${PARTS_DIR}/initrd.gz" &>/dev/null' \
        "Copying initrd.gz to ${PARTS_DIR}"

    run_command 'cat "${PARTS_DIR}/initrd.gz" "${IMAGE_DIR}/firmware.cpio.gz" >"${PARTS_DIR}/${DEBIAN_IMAGE}/install.amd/initrd.gz"' \
        "Appending firmware to initrd.gz"

    # Update checksums
    run_command 'cd "${PARTS_DIR}/${DEBIAN_IMAGE}" && $(md5sum $(find -type f) >md5sum.txt) && cd "${DIR}"' \
        "Updating md5checksum file"

    # Create the image
    run_command 'chmod -R u-w "${PARTS_DIR}/${DEBIAN_IMAGE}" &>/dev/null' \
        "Revoking write permission on image directory"

    if [ -z "${ISO_LABEL}" ]; then
        ISO_LABEL=$(cat "${PARTS_DIR}/${DEBIAN_IMAGE}/.disk/info" | awk '{print $1, $3, $7}')
    fi

    run_command 'xorriso -as mkisofs -r -J \
        -V "${ISO_LABEL}" \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -partition_offset 16 \
        -boot-load-size 4 \
        -boot-info-table \
        -isohybrid-mbr "${PARTS_DIR}/isohdpfx.bin" \
        -o "${OUT_DIR}/${DEBIAN_IMAGE}${ISO_SUFFIX}.iso" "${PARTS_DIR}/${DEBIAN_IMAGE}" \
        &>/dev/null' \
        "Creating new Debian ISO in ${OUT_DIR}/${DEBIAN_IMAGE}${ISO_SUFFIX}.iso"

    # Clean up
    clean_parts
}

# DEFAULTS
ISO_LABEL=""
ISO_SUFFIX=""
DEBIAN_RELEASE="stable"
ARCH="amd64"
PAYLOAD=""

# Parse options
OPTIND=1
while getopts ":l:a:n:p:r:hv" opt; do
    case ${opt} in
    a)
        ARCH="${OPTARG}"
        if [ "${ARCH}" != "arm64" ] && [ "${ARCH}" != "amd64" ]; then
            echo "Invalid architecture specified. Please choose 'arm64' or 'amd64'"
            exit 1
        fi
        ;;

    l)
        ISO_LABEL="${OPTARG}"
        ;;
    h)
        display_help
        exit 0
        ;;
    n)
        ISO_SUFFIX="-${OPTARG}"
        ;;
    p)
        PAYLOAD="${OPTARG}"
        ;;
    r)
        DEBIAN_RELEASE="${OPTARG}"
        if [ "${DEBIAN_RELEASE}" != "stable" ] && [ "${DEBIAN_RELEASE}" != "testing" ]; then
            echo "Invalid release specified. Please choose 'stable' or 'testing'"
            exit 1
        fi
        ;;
    v)
        display_version
        exit 0
        ;;
    \?)
        echo "Invalid option: -${OPTARG}" >&2
        display_help
        exit 1
        ;;
    :)
        echo "Option -${OPTARG} requires an argument" >&2
        display_help
        exit 1
        ;;
    esac
done

# Remove all option arguments
shift $((${OPTIND} - 1))

if [ ! ${#} = 0 ]; then
    display_help
    exit 1
fi

main
