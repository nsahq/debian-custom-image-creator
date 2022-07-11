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
    -h        Print this help message.
    -l STR    ISO volume label.
    -n STR    Append string to ISO name (before .iso).
    -p STR    Payload directory name to add to the image.
    -r STR    Choose release. <stable|testing> Default: stable
    -v        Show version and exit.

## Creating a bootable USB

To create a bootable USB drive from the resulting image do the following:

1. Create your image:

    ```bash
    ./reimager.sh -l NameToBeSeenOnDrive -n mycoolimagename -p mycustompayload -a amd64 -r testing
    ```

2. Insert USB drive

3. Find the assigned device name, e.g. using "dmesg" or "lsblk" (sdc in this example):

    ```bash
    pajken@pjk:~/devstuff/debian-custom-image-creator$ sudo dmesg
    [33120.410997] usb 1-3: new high-speed USB device number 11 using xhci_hcd
    [33120.586113] usb 1-3: New USB device found, idVendor=090c, idProduct=1000, bcdDevice=11.00
    [33120.586116] usb 1-3: New USB device strings: Mfr=1, Product=2, SerialNumber=0
    [33120.586117] usb 1-3: Product: USB DISK
    [33120.586118] usb 1-3: Manufacturer: SMI Corporation
    [33120.599159] usb-storage 1-3:1.0: USB Mass Storage device detected
    [33120.599232] usb-storage 1-3:1.0: Quirks match for vid 090c pid 1000: 400
    [33120.599251] scsi host6: usb-storage 1-3:1.0
    [33121.820110] scsi 6:0:0:0: Direct-Access     SMI      USB DISK         1100 PQ: 0 ANSI: 0 CCS
    [33121.820349] sd 6:0:0:0: Attached scsi generic sg2 type 0
    [33121.820521] sd 6:0:0:0: [sdc] 15730688 512-byte logical blocks: (8.05 GB/7.50 GiB)
    [33121.820876] sd 6:0:0:0: [sdc] Write Protect is off
    [33121.820877] sd 6:0:0:0: [sdc] Mode Sense: 43 00 00 00
    [33121.821233] sd 6:0:0:0: [sdc] No Caching mode page found
    [33121.821237] sd 6:0:0:0: [sdc] Assuming drive cache: write through
    [33121.984803] usb 1-3: reset high-speed USB device number 11 using xhci_hcd
    [33122.504810] usb 1-3: reset high-speed USB device number 11 using xhci_hcd
    [33123.016812] usb 1-3: reset high-speed USB device number 11 using xhci_hcd
    [33123.532819] usb 1-3: reset high-speed USB device number 11 using xhci_hcd
    [33124.056817] usb 1-3: reset high-speed USB device number 11 using xhci_hcd
    [33124.576814] usb 1-3: reset high-speed USB device number 11 using xhci_hcd
    [33124.940571]  sdc: sdc1
    [33125.076819] usb 1-3: reset high-speed USB device number 11 using xhci_hcd
    [33125.592815] usb 1-3: reset high-speed USB device number 11 using xhci_hcd
    ```

    ```bash
    pajken@pjk:~/devstuff/debian-custom-image-creator$ lsblk
    NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
    loop0         7:0    0    47M  1 loop /snap/snapd/16292
    loop1         7:1    0 386.4M  1 loop /snap/anbox/213
    loop2         7:5    0 310.8M  1 loop 
    sda           8:0    0   1.8T  0 disk 
    ├─sda1        8:1    0    16M  0 part 
    └─sda2        8:2    0   1.8T  0 part 
    sdb           8:16   0 931.5G  0 disk 
    └─sdb1        8:17   0 931.5G  0 part 
    sdc           8:32   1   7.5G  0 disk 
    └─sdc1        8:33   1   613M  0 part /media/pajken/PajkOS
    nvme0n1     259:0    0 931.5G  0 disk 
    ├─nvme0n1p1 259:1    0   100M  0 part /boot/efi
    ├─nvme0n1p2 259:2    0    16M  0 part 
    ├─nvme0n1p3 259:3    0 155.6G  0 part 
    ├─nvme0n1p4 259:4    0   499M  0 part 
    ├─nvme0n1p5 259:5    0   498G  0 part 
    ├─nvme0n1p6 259:6    0 276.3G  0 part /
    └─nvme0n1p7 259:7    0   977M  0 part [SWAP]
    ```

4. Copy your new image to the device where sdx is replaced by your device name:

    ```bash
    sudo dd bs=4M if=out/debian-iso-filename.iso of=/dev/sdx status=progress oflag=sync
    ```

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
