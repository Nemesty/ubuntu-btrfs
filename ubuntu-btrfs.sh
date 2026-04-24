#!/bin/bash

# --- Configuration ---
MOUNT_POINT="/mnt/btrfs_setup"
OPTIONS="noatime,compress=zstd:3,discard=async"

echo "🔍 Recherche de la partition Btrfs..."

# Identification dynamique de la partition Btrfs
DEV=$(blkid -t TYPE=btrfs -o device | head -n 1)
UUID=$(blkid -s UUID -o value "$DEV")

if [ -z "$DEV" ]; then
    echo "❌ Erreur : Aucune partition Btrfs détectée !"
    exit 1
fi

echo "📍 Partition trouvée : $DEV"
echo "🆔 UUID : $UUID"

# 1. Montage de la racine de la partition
sudo mkdir -p "$MOUNT_POINT"
sudo mount "$DEV" "$MOUNT_POINT"

echo "📦 Restructuration en sous-volumes..."
cd "$MOUNT_POINT" || exit

# Création du sous-volume racine @ et transfert des données
if [ ! -d "@" ]; then
    sudo btrfs subvolume create @
    # On déplace tout vers @ sauf les dossiers système de la session Live et le dossier @ lui-même
    sudo find . -maxdepth 1 ! -name '@' ! -name '.' -exec mv {} @/ \;
fi

# Création des autres sous-volumes
for sub in @home @log @cache @tmp; do
    [ ! -d "$sub" ] && sudo btrfs subvolume create "$sub"
done

# Migration des données si elles existent (cas d'une installation fraîche)
[ -d "@/home" ] && sudo mv @/home/* @home/ 2>/dev/null
[ -d "@/var/log" ] && sudo mv @/var/log/* @log/ 2>/dev/null
[ -d "@/var/cache" ] && sudo mv @/var/cache/* @cache/ 2>/dev/null

# 2. Mise à jour du fstab
echo "📝 Configuration du fichier /etc/fstab..."
cat <<EOF | sudo tee @/etc/fstab
# /etc/fstab: static file system information.
UUID=$UUID /           btrfs $OPTIONS,subvol=@ 0 0
UUID=$UUID /home       btrfs $OPTIONS,subvol=@home 0 0
UUID=$UUID /var/log    btrfs $OPTIONS,subvol=@log 0 0
UUID=$UUID /var/cache  btrfs $OPTIONS,subvol=@cache 0 0
UUID=$UUID /tmp        btrfs $OPTIONS,subvol=@tmp 0 0
EOF

# 3. Réparation du Bootloader (GRUB)
echo "🔧 Réparation de GRUB (Chroot)..."
# Montage des partitions virtuelles pour le chroot
for i in /dev /dev/pts /proc /sys /run; do sudo mount -B $i "@$i"; done

# On détecte le disque (ex: /dev/sda1 -> /dev/sda)
DISK=$(echo "$DEV" | sed 's/[0-9]*$//')

sudo chroot @ /bin/bash <<CHROOT_EOF
grub-install $DISK
update-grub
CHROOT_EOF

# Démontage propre
echo "🧹 Nettoyage..."
for i in /run /sys /proc /dev/pts /dev; do sudo umount "@$i"; done
cd /
sudo umount "$MOUNT_POINT"

echo "---"
echo "✅ Terminé ! Tu peux maintenant redémarrer ton PC normalement."
