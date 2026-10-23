#!/usr/bin/env bash
# Copies the firmware of all USB WiFi drivers from linux-firmware: the
# firmware declared (MODULE_FIRMWARE) by every wireless module with a USB
# device alias and by the modules it depends on, which is where e.g.
# rtw88 and mt76 declare it.
#
# Firmware for PCIe and SDIO chips is skipped, brcmfmac declares it for
# all buses. Files not in linux-firmware are skipped as well.
#
# usage: usb-wifi-firmware.sh MODULES_TREE KERNEL_VERSION FIRMWARE_DIR OUT_DIR
set -euo pipefail

tree=$1
version=$2
firmware=$3
out=$4

modinfo() {
    command modinfo -b "$tree" -k "$version" "$@"
}

queue=()
for ko in $(find "$tree/lib/modules/$version/kernel/drivers/net/wireless" -name '*.ko*'); do
    if modinfo -F alias "$ko" | grep -q '^usb:'; then
        queue+=("$(basename "$ko" | sed 's/\.ko.*//')")
    fi
done

declare -A modules
i=0
while [ $i -lt ${#queue[@]} ]; do
    m=${queue[$i]}
    i=$((i + 1))
    [ -n "${modules[$m]:-}" ] && continue
    modules[$m]=1
    for dep in $(modinfo -F depends "$m" | tr ',' ' '); do
        queue+=("$dep")
    done
done

for m in "${!modules[@]}"; do
    modinfo -F firmware "$m"
done | sort -u | while read -r f; do
    case $f in
        *-pcie* | *-sdio*) continue ;;
    esac
    if [ -e "$firmware/$f" ]; then
        install -Dm644 "$firmware/$f" "$out/$f"
    fi
done
