# Debian custom hybrid image creator

Rebuild a Debian ISO with firware from the non-free repository and custom
changes using your own payload.

Downloads the Debian ISO, firmware, and/or checksum files if not already
present, and will redownload the ISO and/or firmware if their respective
checksums do not match their checksum file.

Firmwares are appended to the unpacked image's initrd.gz file, and the contents
of the 'payload' folder is copied into the unpacked image's root folder. The
unpacked image is then repackaged and placed into the 'out' folder.

## Usage

Usage: reimager.sh [options]

    -a STR    Architecture. <arm64|amd64> Default: amd64
    -l STR    ISO volume label.
    -n STR    Append string to ISO name (before .iso).
    -h        Print this help message.
    -r STR    Choose release. <stable|testing> Default: stable
    -v        Show version and exit.

## More info

The script will create following
directories locally:

* cache - Cache of Debian images and checksum files
* out - The directory where your resulting image will reside
* parts - Temporary directory used by the script to assemble the image
* payload - Where your custom payloads should reside in a sub directory

Payloads can consist of anything you wish to include in the image, e.g. preseed files,
custom firmwares, grub configs etc. etc.

Debian images and firmwares are cached locally. To force the script to fetch
new images, remove the cache directory (or image/checksums therein).
