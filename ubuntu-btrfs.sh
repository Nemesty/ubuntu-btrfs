#!/bin/bash

# --- Configuration ---
MOUNT_POINT="/mnt/btrfs_fix"
OPTIONS="noatime,compress=zstd:3,discard=async"

echo "🔍 Détection de la partition..."
DEV=$(blkid -t TYPE=btrfs -o device | head -n 1)
UUID=$(blkid -s UUID -o value "$DEV")

if [ -z "$DEV" ]; then
    echo "❌ Erreur : Partition Btrfs introuvable."
    exit 1
fi

# 1. Préparation du montage propre
sudo mkdir -p "$MOUNT_POINT"
sudo mount "$DEV" "$MOUNT_POINT"
cd "$MOUNT_POINT"

# 2. Création de la structure (si pas déjà fait)
if [ ! -d "@" ]; then
    echo "📦 Création des sous-volumes..."
    sudo btrfs subvolume create @
    sudo find . -maxdepth 1 ! -name '@' ! -name '.' -exec mv {} @/ \;
    for sub in @home @log @cache @tmp; do
        sudo btrfs subvolume create "$sub"
    done
fi

# 3. Mise à jour du fstab
echo "📝 Mise à jour du fstab..."
cat <<EOF | sudo tee @/etc/fstab
# /etc/fstab
UUID=$UUID /           btrfs $OPTIONS,subvol=@ 0 0
UUID=$UUID /home       btrfs $OPTIONS,subvol=@home 0 0
UUID=$UUID /var/log    btrfs $OPTIONS,subvol=@log 0 0
UUID=$UUID /var/cache  btrfs $OPTIONS,subvol=@cache 0 0
UUID=$UUID /tmp        btrfs $OPTIONS,subvol=@tmp 0 0
EOF

# 4. LE CHROOT CORRECT (Essentiel pour GRUB)
echo "🔧 Entrée en environnement Chroot..."
# On démonte pour remonter spécifiquement le sous-volume @ sur /mnt
cd /
sudo umount "$MOUNT_POINT"
sudo mount -o subvol=@ "$DEV" "$MOUNT_POINT"

# Montage des dossiers vitaux
for i in /dev /dev/pts /proc /sys /run; do sudo mount -B $i "$MOUNT_POINT$i"; done

# 5. Réinstallation forcée de GRUB
echo "💿 Réinstallation de GRUB sur /dev/sda..."
sudo chroot "$MOUNT_POINT" /bin/bash <<CHROOT_EOF
# On force GRUB à ignorer les erreurs de détection de périphérique
grub-install --recheck /dev/sda
update-grub
CHROOT_EOF

# 6. Nettoyage
echo "🧹 Nettoyage des montages..."
for i in /run /sys /proc /dev/pts /dev; do sudo umount "$MOUNT_POINT$i"; done
sudo umount "$MOUNT_POINT"

echo "✅ Terminé ! Tu peux redémarrer."
