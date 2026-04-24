#!/bin/bash

# --- Configuration ---
MOUNT_POINT="/mnt/ubuntu_repair"
OPTIONS="noatime,compress=zstd:3,discard=async"

echo "🔍 Analyse du disque..."

# 1. Identification de la partition Btrfs
DEV=$(blkid -t TYPE=btrfs -o device | head -n 1)
UUID=$(blkid -s UUID -o value "$DEV")
DISK="/dev/sda"

if [ -z "$DEV" ]; then
    echo "❌ Erreur : Aucune partition Btrfs trouvée !"
    exit 1
fi

echo "📍 Cible : $DEV (UUID: $UUID)"

# 2. Nettoyage préventif
sudo umount -R "$MOUNT_POINT" 2>/dev/null
sudo mkdir -p "$MOUNT_POINT"

# 3. Montage du sous-volume @ comme racine
echo "📂 Montage du sous-volume racine (@)..."
sudo mount -o subvol=@ "$DEV" "$MOUNT_POINT"

# 4. Préparation du terrain pour GRUB
echo "🔗 Liaison des systèmes de fichiers..."
for i in /dev /dev/pts /proc /sys /run; do
    sudo mount -B "$i" "$MOUNT_POINT$i"
done

# 5. Réparation de GRUB et mise à jour fstab
echo "🔧 Réinstallation de GRUB sur $DISK..."
sudo chroot "$MOUNT_POINT" /bin/bash <<CHROOT_EOF
# Mise à jour du fstab à l'intérieur du système
cat <<FSTAB > /etc/fstab
UUID=$UUID /           btrfs $OPTIONS,subvol=@ 0 0
UUID=$UUID /home       btrfs $OPTIONS,subvol=@home 0 0
UUID=$UUID /var/log    btrfs $OPTIONS,subvol=@log 0 0
UUID=$UUID /var/cache  btrfs $OPTIONS,subvol=@cache 0 0
UUID=$UUID /tmp        btrfs $OPTIONS,subvol=@tmp 0 0
FSTAB

# Réinstallation forcée
grub-install --recheck $DISK
update-grub
CHROOT_EOF

# 6. Démontage
echo "🧹 Nettoyage final..."
sudo umount -R "$MOUNT_POINT"

echo "-------------------------------------------------------"
echo "✅ Réparation terminée ! Tu peux redémarrer maintenant."
