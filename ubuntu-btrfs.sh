#!/bin/bash
# Migration Btrfs sécurisée - Ubuntu 26.04
set -euo pipefail

# --- CONFIG ---
DEV_ROOT="/dev/sda1"
DEV_EFI="/dev/sda2"
DISK="/dev/sda"

MNT_ROOT="/mnt/btrfs_root"
MNT_SYS="/mnt/system_chroot"

OPTIONS="noatime,compress=zstd:3,discard=async"
LOGFILE="/tmp/btrfs_migration.log"

exec > >(tee -a "$LOGFILE") 2>&1

echo "=== 🚀 DÉBUT MIGRATION BTRFS ==="

# --- SÉCURITÉ ---
if [ "$EUID" -ne 0 ]; then
    echo "❌ Doit être exécuté en root"
    exit 1
fi

if ! blkid "$DEV_ROOT" | grep -q btrfs; then
    echo "❌ $DEV_ROOT n'est pas en Btrfs"
    exit 1
fi

if mount | grep " / " | grep -q "$DEV_ROOT"; then
    echo "❌ Tu es booté sur le disque (pas en live)"
    exit 1
fi

# --- MONTAGE RACINE ---
mkdir -p "$MNT_ROOT"
mount -t btrfs -o subvolid=5 "$DEV_ROOT" "$MNT_ROOT"

# --- SNAPSHOT BACKUP ---
echo "📸 Snapshot de sécurité..."
SNAP_NAME="@pre_migration_$(date +%Y%m%d_%H%M%S)"
btrfs subvolume snapshot "$MNT_ROOT" "$MNT_ROOT/$SNAP_NAME"

# --- CRÉATION SUBVOLUMES ---
echo "📦 Création des sous-volumes..."
for sub in @ @home @log @cache @tmp; do
    if ! btrfs subvolume list "$MNT_ROOT" | grep -q " $sub$"; then
        btrfs subvolume create "$MNT_ROOT/$sub"
    fi
done

# --- MIGRATION ROOT ---
echo "🚚 Copie des données vers @ (rsync sécurisé)..."
rsync -aAXH --info=progress2 \
    --exclude="@*" \
    "$MNT_ROOT/" "$MNT_ROOT/@/"

# --- MIGRATION DOSSIERS ---
echo "📂 Réorganisation des dossiers..."

rsync -aAX "$MNT_ROOT/@/home/" "$MNT_ROOT/@home/" || true
rsync -aAX "$MNT_ROOT/@/var/log/" "$MNT_ROOT/@log/" || true
rsync -aAX "$MNT_ROOT/@/var/cache/" "$MNT_ROOT/@cache/" || true
rsync -aAX "$MNT_ROOT/@/tmp/" "$MNT_ROOT/@tmp/" || true

# --- NETTOYAGE SAFE ---
echo "🧹 Nettoyage contrôlé..."

rm -rf "$MNT_ROOT/@/home"/*
rm -rf "$MNT_ROOT/@/var/log"/*
rm -rf "$MNT_ROOT/@/var/cache"/*
rm -rf "$MNT_ROOT/@/tmp"/*

mkdir -p "$MNT_ROOT/@/var/log"
mkdir -p "$MNT_ROOT/@/var/cache"
mkdir -p "$MNT_ROOT/@/tmp"
chmod 1777 "$MNT_ROOT/@/tmp"

# --- FSTAB ---
echo "📝 Configuration fstab..."

UUID_ROOT=$(blkid -s UUID -o value "$DEV_ROOT")
UUID_EFI=$(blkid -s UUID -o value "$DEV_EFI")

cp "$MNT_ROOT/@/etc/fstab" "$MNT_ROOT/@/etc/fstab.backup"

cat <<EOF > "$MNT_ROOT/@/etc/fstab"
# /etc/fstab - Btrfs optimisé
UUID=$UUID_ROOT /           btrfs defaults,subvol=@,$OPTIONS 0 1
UUID=$UUID_ROOT /home       btrfs defaults,subvol=@home,$OPTIONS 0 2
UUID=$UUID_ROOT /var/log    btrfs defaults,subvol=@log,$OPTIONS 0 2
UUID=$UUID_ROOT /var/cache  btrfs defaults,subvol=@cache,$OPTIONS 0 2
UUID=$UUID_ROOT /tmp        btrfs defaults,subvol=@tmp,$OPTIONS 0 2
UUID=$UUID_EFI  /boot/efi   vfat  defaults 0 1
EOF

# --- CHROOT ---
echo "🔧 Configuration GRUB..."

mkdir -p "$MNT_SYS"
mount -t btrfs -o subvol=@ "$DEV_ROOT" "$MNT_SYS"
mount "$DEV_EFI" "$MNT_SYS/boot/efi"

for i in /dev /dev/pts /proc /sys /run; do
    mount --bind "$i" "$MNT_SYS$i"
done

chroot "$MNT_SYS" /bin/bash -c "
set -e
grub-install $DISK
update-grub
"

# --- VÉRIFICATION ---
echo "🔍 Vérification finale..."

btrfs subvolume list "$MNT_ROOT"

# --- NETTOYAGE ---
echo "🧼 Nettoyage..."

umount -R "$MNT_SYS"
umount "$MNT_ROOT"

echo "✅ Migration terminée avec succès !"
echo "📄 Log disponible : $LOGFILE"
echo "📸 Snapshot disponible : $SNAP_NAME"
echo "👉 Tu peux redémarrer."
