#!/bin/bash

L_PLATFORM=$(echo $PLATFORM | tr '[:upper:]' '[:lower:]')
KERNEL_MINOR_VERSION=$(echo $KERNEL_VERSION | cut -d. -f1,2)

# Setup Synology package toolkit framework
git clone -b DSM7.2 https://github.com/SynologyOpenSource/pkgscripts-ng /toolkit/pkgscripts-ng
/toolkit/pkgscripts-ng/EnvDeploy -v $(echo $DSM_VERSION | cut -d- -f1) -p $L_PLATFORM

# Setup Synology toolchain
wget https://global.synologydownload.com/download/ToolChain/toolchain/$DSM_VERSION/Intel%20x86%20Linux%20$KERNEL_VERSION%20%28$PLATFORM%29/$L_PLATFORM-gcc1220_glibc236_x86_64-GPL.txz
TOOLCHAIN_FOLDER=$(tar -tJf "$L_PLATFORM-gcc1220_glibc236_x86_64-GPL.txz" | head -n 1 | cut -d/ -f1)
tar -xJf "$L_PLATFORM-gcc1220_glibc236_x86_64-GPL.txz" -C /usr/local/

# Setup Synology kernel
wget https://global.synologydownload.com/download/ToolChain/Synology%20NAS%20GPL%20Source/$DSM_VERSION/$L_PLATFORM/linux-$KERNEL_MINOR_VERSION.x.txz
KERNEL_FOLDER=$(tar -tJf linux-$KERNEL_MINOR_VERSION.x.txz | head -n 1 | cut -d/ -f1)
tar -xJf linux-$KERNEL_MINOR_VERSION.x.txz -C /usr/local/$TOOLCHAIN_FOLDER/
cp /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/synoconfigs/$L_PLATFORM /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/.config
CONFIG_CROSS_COMPILE=$(printf '%s\n' "/usr/local/$TOOLCHAIN_FOLDER/bin/$TOOLCHAIN_FOLDER-" | sed 's/[\/&]/\\&/g')
sed -i "s/CONFIG_CROSS_COMPILE=\"\"/CONFIG_CROSS_COMPILE=\"$CONFIG_CROSS_COMPILE\"/" /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/.config

# Setup WireGuard
git clone https://git.zx2c4.com/wireguard-linux-compat
sed -i "s|KERNELDIR ?= .*|KERNELDIR ?= /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER|" wireguard-linux-compat/src/Makefile
sed -i "s|KERNELRELEASE ?= .*|KERNELRELEASE ?= $KERNEL_VERSION|" wireguard-linux-compat/src/Makefile

# Override kernel configs
jq -r 'to_entries[] | "\(.key) \(.value)"' config_modification.json | while read -r key value; do
  sed -i "s|[# ].*$key.*|$value|" /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/.config

  if ! grep -q "^$key=" /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/.config; then
    echo "$value" >> /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/.config
  fi
done

# Build
ARCH=$(echo $TOOLCHAIN_FOLDER | cut -d- -f1)
yes "" | make -C /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER oldconfig ARCH=$ARCH
make -C /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER prepare ARCH=$ARCH
make -C /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER modules_prepare ARCH=$ARCH
make -C /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER modules -j$(nproc) KBUILD_MODPOST_NOFINAL=1 ARCH=$ARCH

# Build the modules we need
make -C /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER -j$(nproc) M=net/ipv4/netfilter modules ARCH=$ARCH
make -C /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER -j$(nproc) M=net/ipv6/netfilter modules ARCH=$ARCH
make -C /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER -j$(nproc) M=net/netfilter modules ARCH=$ARCH
make -C /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER -j$(nproc) M=drivers/usb/serial modules ARCH=$ARCH
make -C wireguard-linux-compat/src -j$(nproc) ARCH=$ARCH

# Collect output
OUTPUT_FOLDER="./output/${PLATFORM}_${DSM_VERSION}_${KERNEL_VERSION}"
mkdir -p $OUTPUT_FOLDER
cp /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/net/ipv4/netfilter/iptable_raw.ko $OUTPUT_FOLDER
cp /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/net/ipv6/netfilter/ip6table_raw.ko $OUTPUT_FOLDER
cp /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/net/netfilter/xt_comment.ko $OUTPUT_FOLDER
cp /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/net/netfilter/xt_connmark.ko $OUTPUT_FOLDER
cp /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/drivers/usb/serial/cp210x.ko $OUTPUT_FOLDER
cp /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/drivers/usb/serial/ch341.ko $OUTPUT_FOLDER
cp /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/drivers/usb/serial/pl2303.ko $OUTPUT_FOLDER
cp /usr/local/$TOOLCHAIN_FOLDER/$KERNEL_FOLDER/drivers/usb/serial/ti_usb_3410_5052.ko $OUTPUT_FOLDER
cp wireguard-linux-compat/src/wireguard.ko $OUTPUT_FOLDER