#!/usr/bin/env bash

set -euo pipefail

KERNEL_DIR="${GITHUB_WORKSPACE}/kernel"
OUT_DIR="${GITHUB_WORKSPACE}/output"

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

mkdir -p "${OUT_DIR}"

cd "${KERNEL_DIR}"

echo "=== Kernel ==="
git describe --always --dirty
git rev-parse HEAD

echo
echo "=== Finding R36S configuration ==="

CONFIG=""

for candidate in \
    arch/arm64/configs/r36s_defconfig \
    arch/arm64/configs/r36s_android_defconfig \
    arch/arm64/configs/lineage_r36s_defconfig
do
    if [ -f "$candidate" ]; then
        CONFIG="$candidate"
        break
    fi
done

if [ -z "$CONFIG" ]; then
    echo "Could not automatically find R36S defconfig."
    echo
    echo "Available ARM64 defconfigs:"
    find arch/arm64/configs -type f | sort
    exit 1
fi

echo "Using: ${CONFIG}"

DEFCONFIG="$(basename "${CONFIG}")"

echo
echo "=== Loading kernel configuration ==="

make "${DEFCONFIG}"

echo
echo "=== Enabling USB Ethernet modules ==="

./scripts/config --module USB_NET
./scripts/config --module USB_NET_RNDIS_HOST
./scripts/config --module USB_NET_CDCETHER

make olddefconfig

echo
echo "=== Resulting configuration ==="

grep -E \
    'CONFIG_USB_NET(=|_)|CONFIG_USB_NET_RNDIS_HOST|CONFIG_USB_NET_CDCETHER' \
    .config || true

echo
echo "=== Building USB networking modules ==="

make -j"$(nproc)" \
    M=drivers/net/usb \
    modules

echo
echo "=== Copying modules ==="

for module in \
    usbnet \
    rndis_host \
    cdc_ether
do
    if [ -f "drivers/net/usb/${module}.ko" ]; then
        cp "drivers/net/usb/${module}.ko" "${OUT_DIR}/"
    else
        echo "ERROR: ${module}.ko was not produced"
        exit 1
    fi
done

echo
echo "=== Generating module dependency information ==="

cd "${OUT_DIR}"

depmod \
    -b "${OUT_DIR}/root" \
    "$(make -s -C "${KERNEL_DIR}" kernelversion)"

if [ -d "${OUT_DIR}/root/lib/modules" ]; then
    find "${OUT_DIR}/root/lib/modules" -type f -print
fi

echo
echo "=== Finished ==="

ls -lh "${OUT_DIR}"/*.ko
