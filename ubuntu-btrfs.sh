#!/bin/bash

# --- Configuration ---
TARGET="/target"
OPTIONS="noatime,compress=zstd:3,discard=async"

echo "🚀 Détection de la configuration système..."

# Récupération dynamique du périphérique et de l'UUID
DEV=$(findmnt -n -o SOURCE "$TARGET")
UUID=$(blkid -s UUID -o value "$DEV")

if [ -z "$UUID" ]; then
    echo "❌ Erreur : Impossible de trouver l'UUID pour $TARGET. Est-ce que la partition est bien montée ?"
    exit 1
fi

echo "📍 Périphérique détecté : $DEV"
echo "🆔 UUID détecté : $UUID"

# 1. Création de la structure de sous-volumes
cd "$TARGET" || exit
echo "📦 Création des sous-volumes..."

# Création du root et déplacement du système
btrfs subvolume create @
find . -maxdepth 1 ! -name '@' ! -name '.' -exec mv {} @/ \;

# Création des autres points de montage
btrfs subvolume create @home
btrfs subvolume create @log
btrfs subvolume create @cache
btrfs subvolume create @tmp

# Migration des données existantes
[ -d "@/home" ] && mv @/home/* @home/ 2>/dev/null
[ -d "@/var/log" ] && mv @/var/log/* @log/ 2>/dev/null
[ -d "@/var/cache" ] && mv @/var/cache/* @cache/ 2>/dev/null

# 2. Génération du fstab dynamique
echo "📝 Mise à jour du fichier /etc/fstab..."
cat <<EOF > @/etc/fstab
# /etc/fstab: static file system information.
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=$UUID /           btrfs $OPTIONS,subvol=@ 0 0
UUID=$UUID /home       btrfs $OPTIONS,subvol=@home 0 0
UUID=$UUID /var/log    btrfs $OPTIONS,subvol=@log 0 0
UUID=$UUID /var/cache  btrfs $OPTIONS,subvol=@cache 0 0
UUID=$UUID /tmp        btrfs $OPTIONS,subvol=@tmp 0 0
EOF

# 3. Réparation de GRUB (Chroot)
echo "🔧 Réinstallation de GRUB sur ${DEV%?}..." # Enlève le numéro de partition (ex: sda1 -> sda)
# Montage des systèmes de fichiers virtuels
for i in /dev /dev/pts /proc /sys /run; do mount -B $i @$i; done

# Exécution du chroot pour réparer le bootloader
chroot @ /bin/bash <<CHROOT_EOF
grub-install ${DEV%?}
update-grub
CHROOT_EOF

# Nettoyage
for i in /run /sys /proc /dev/pts /dev; do umount @$i; done

echo "---"
echo "✅ Configuration terminée avec succès pour l'UUID $UUID !"
echo "Tu peux maintenant démonter /target et redémarrer."
