#!/bin/bash
# Script simplifié Btrfs pour Ubuntu
# Crée les sous-volumes essentiels et configure fstab

set -e

[ "$(id -u)" -eq 0 ] || { echo "❌ Ce script doit être exécuté en root."; exit 1; }

ROOT_DEV="/dev/sda1"
BOOT_DEV="/dev/sda2"
MNT="/mnt"

echo "🔧 Préparation de l'environnement..."
umount /target 2>/dev/null || true
mkdir -p "$MNT"

echo "📦 Montage de la partition Btrfs..."
mount "$ROOT_DEV" "$MNT"
cd "$MNT"

echo "📁 Création du sous-volume racine (@)..."
btrfs subvolume snapshot . @

echo "🧹 Nettoyage de la racine..."
find . -maxdepth 1 ! -name "@*" ! -name "." -exec rm -rf {} +

echo "📁 Création des sous-volumes..."
for subvol in @home @log @cache @tmp; do
    btrfs subvolume create "$subvol"
done

echo "📂 Organisation des dossiers existants..."
[ -d var/log ] && mv var/log/* @log/ 2>/dev/null || true
[ -d var/cache ] && mv var/cache/* @cache/ 2>/dev/null || true

cd /
umount "$MNT"

echo "🔄 Remontage avec le sous-volume racine..."
mount -o subvol=@ "$ROOT_DEV" "$MNT"

echo "📝 Configuration de /etc/fstab..."
UUID=$(blkid -s UUID -o value "$ROOT_DEV")
FSTAB="$MNT/etc/fstab"

# Nettoyage anciennes entrées Btrfs
sed -i "/btrfs/d" "$FSTAB"

cat <<EOF >> "$FSTAB"
UUID=$UUID / btrfs defaults,noatime,discard=async,compress=zstd:3,subvol=@ 0 0
UUID=$UUID /home btrfs defaults,noatime,discard=async,compress=zstd:3,subvol=@home 0 0
UUID=$UUID /var/log btrfs defaults,noatime,discard=async,compress=zstd:3,subvol=@log 0 0
UUID=$UUID /var/cache btrfs defaults,noatime,discard=async,compress=zstd:3,subvol=@cache 0 0
UUID=$UUID /tmp btrfs defaults,noatime,discard=async,compress=zstd:3,subvol=@tmp 0 0
EOF

echo "🔧 Mise à jour de GRUB..."
mount "$BOOT_DEV" "$MNT/boot"

for dir in proc sys dev run; do
    mount --bind /$dir "$MNT/$dir"
done

chroot "$MNT" update-grub
chroot "$MNT" update-initramfs -u

echo "🧹 Nettoyage..."
for dir in proc sys dev run; do
    umount "$MNT/$dir" 2>/dev/null || true
done

umount "$MNT/boot" 2>/dev/null || true
umount "$MNT" 2>/dev/null || true

echo "✅ Configuration terminée !"
echo "🔁 Redémarre avant d'installer Snapper ou Timeshift."
