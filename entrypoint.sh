#!/bin/bash

L_PLATFORM=$(echo $PLATFORM | tr '[:upper:]' '[:lower:]')
KERNEL_VERSION="${KERNEL_MAJORVERSION}.${KERNEL_PATCHLEVEL}.${KERNEL_SUBLEVEL}"
KERNEL_MINOR_VERSION="${KERNEL_MAJORVERSION}.${KERNEL_PATCHLEVEL}"
S_DSM_VERSION=$(echo $DSM_VERSION | cut -d- -f1)
SOURCE_PATH="/toolkit/build_env/ds.$L_PLATFORM-$S_DSM_VERSION/source"

# Setup Synology package toolkit framework
git clone -b DSM7.2 https://github.com/SynologyOpenSource/pkgscripts-ng /toolkit/pkgscripts-ng
/toolkit/pkgscripts-ng/EnvDeploy -v $S_DSM_VERSION -p $L_PLATFORM

# Setup Synology kernel
wget https://global.synologydownload.com/download/ToolChain/Synology%20NAS%20GPL%20Source/$DSM_VERSION/$L_PLATFORM/linux-$KERNEL_MINOR_VERSION.x.txz
KERNEL_FOLDER=$(tar -tJf linux-$KERNEL_MINOR_VERSION.x.txz | head -n 1 | cut -d/ -f1)
tar -xJf linux-$KERNEL_MINOR_VERSION.x.txz -C $SOURCE_PATH/
KERNEL_PATH=$SOURCE_PATH/$KERNEL_FOLDER
cp $KERNEL_PATH/synoconfigs/$L_PLATFORM $KERNEL_PATH/.config
sed -i "s/^VERSION.*/VERSION = $KERNEL_MAJORVERSION/" $KERNEL_PATH/Makefile
sed -i "s/^PATCHLEVEL.*/PATCHLEVEL = $KERNEL_PATCHLEVEL/" $KERNEL_PATH/Makefile
sed -i "s/^SUBLEVEL.*/SUBLEVEL = $KERNEL_SUBLEVEL/" $KERNEL_PATH/Makefile
sed -i "s/^EXTRAVERSION.*/EXTRAVERSION = $KERNEL_EXTRAVERSION/" $KERNEL_PATH/Makefile

# Setup WireGuard
git clone https://git.zx2c4.com/wireguard-linux-compat $SOURCE_PATH/wireguard-linux-compat
sed -i "s|KERNELDIR ?= .*|KERNELDIR ?= /source/$KERNEL_FOLDER|" $SOURCE_PATH/wireguard-linux-compat/src/Makefile
sed -i "s|KERNELRELEASE ?= .*|KERNELRELEASE ?= $KERNEL_VERSION|" $SOURCE_PATH/wireguard-linux-compat/src/Makefile

# Override kernel configs
jq -r 'to_entries[] | "\(.key) \(.value)"' config_modification.json | while read -r key value; do
  sed -i "s|[# ].*$key.*|$value|" $KERNEL_PATH/.config

  if ! grep -q "^$key=" $KERNEL_PATH/.config; then
    echo "$value" >> $KERNEL_PATH/.config
  fi
done

# Build
chroot /toolkit/build_env/ds.$L_PLATFORM-$S_DSM_VERSION/ /bin/bash <<EOF
KERNEL_PATH="/source/$KERNEL_FOLDER"
make -C \$KERNEL_PATH oldconfig
make -C \$KERNEL_PATH prepare
make -C \$KERNEL_PATH modules_prepare
make -C \$KERNEL_PATH modules -j$(nproc) KBUILD_MODPOST_NOFINAL=1

# Build the modules we need
make -C \$KERNEL_PATH -j$(nproc) M=net/ipv4/netfilter modules
make -C \$KERNEL_PATH -j$(nproc) M=net/ipv6/netfilter modules
make -C \$KERNEL_PATH -j$(nproc) M=net/netfilter modules
make -C \$KERNEL_PATH -j$(nproc) M=drivers/usb/serial modules
make -C /source/wireguard-linux-compat/src -j$(nproc)
EOF

# Collect output
OUTPUT_FOLDER="./output/${PLATFORM}_${DSM_VERSION}_${KERNEL_VERSION}"
mkdir -p $OUTPUT_FOLDER
cp $KERNEL_PATH/net/ipv4/netfilter/iptable_raw.ko $OUTPUT_FOLDER
cp $KERNEL_PATH/net/ipv6/netfilter/ip6table_raw.ko $OUTPUT_FOLDER
cp $KERNEL_PATH/net/netfilter/xt_comment.ko $OUTPUT_FOLDER
cp $KERNEL_PATH/net/netfilter/xt_connmark.ko $OUTPUT_FOLDER
cp $KERNEL_PATH/drivers/usb/serial/cp210x.ko $OUTPUT_FOLDER
cp $KERNEL_PATH/drivers/usb/serial/ch341.ko $OUTPUT_FOLDER
cp $KERNEL_PATH/drivers/usb/serial/pl2303.ko $OUTPUT_FOLDER
cp $KERNEL_PATH/drivers/usb/serial/ti_usb_3410_5052.ko $OUTPUT_FOLDER
cp $SOURCE_PATH/wireguard-linux-compat/src/wireguard.ko $OUTPUT_FOLDER