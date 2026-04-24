#!/bin/bash

# --- Configuration ---
MOUNT_POINT="/mnt/btrfs_efi"
OPTIONS="noatime,compress=zstd:3,discard=async"

echo "🔍 Analyse du disque (Mode EFI)..."

# 1. Détection des partitions
DEV_BTRFS=$(blkid -t TYPE=btrfs -o device | head -n 1)
DEV_EFI=$(blkid -t TYPE=vfat -o device | head -n 1) # Cherche la partition FAT32 (EFI)
UUID_BTRFS=$(blkid -s UUID -o value "$DEV_BTRFS")
UUID_EFI=$(blkid -s UUID -o value "$DEV_EFI")

if [ -z "$DEV_BTRFS" ] || [ -z "$DEV_EFI" ]; then
    echo "❌ Erreur : Partition Btrfs ou EFI introuvable."
    exit 1
fi

echo "📍 Btrfs : $DEV_BTRFS"
echo "📍 EFI   : $DEV_EFI"

# 2. Montage du sous-volume racine @
sudo mkdir -p "$MOUNT_POINT"
sudo mount -o subvol=@ "$DEV_BTRFS" "$MOUNT_POINT"

# 3. Montage de la partition EFI et des dossiers système
sudo mount "$DEV_EFI" "$MOUNT_POINT/boot/efi"
for i in /dev /dev/pts /proc /sys /run; do sudo mount -B $i "$MOUNT_POINT$i"; done

# 4. Mise à jour du fstab (avec EFI)
echo "📝 Mise à jour du fstab..."
cat <<EOF | sudo tee "$MOUNT_POINT/etc/fstab"
# /etc/fstab
UUID=$UUID_BTRFS /           btrfs $OPTIONS,subvol=@ 0 0
UUID=$UUID_BTRFS /home       btrfs $OPTIONS,subvol=@home 0 0
UUID=$UUID_BTRFS /var/log    btrfs $OPTIONS,subvol=@log 0 0
UUID=$UUID_BTRFS /var/cache  btrfs $OPTIONS,subvol=@cache 0 0
UUID=$UUID_BTRFS /tmp        btrfs $OPTIONS,subvol=@tmp 0 0
UUID=$UUID_EFI   /boot/efi   vfat  umask=0077      0 1
EOF

# 5. Réinstallation de GRUB EFI
echo "🔧 Réinstallation de GRUB EFI..."
sudo chroot "$MOUNT_POINT" /bin/bash <<CHROOT_EOF
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck
update-grub
CHROOT_EOF

# 6. Nettoyage
echo "🧹 Démontage..."
sudo umount -R "$MOUNT_POINT"

echo "✅ Terminé pour EFI ! Tu peux redémarrer."
