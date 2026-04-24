#!/bin/bash

# --- Configuration ---
TARGET="/target"
DEV="/dev/sda1"
UUID="844149eb-3014-452d-bee0-4a5dc4d89a6a"
OPTIONS="noatime,compress=zstd:3,discard=async"

echo "🚀 Restructuration Btrfs et réparation du démarrage..."

# 1. Création de la structure de sous-volumes
cd $TARGET
echo "📦 Création des sous-volumes (@, @home, @log, @cache, @tmp)..."

# Création du root et déplacement du système
btrfs subvolume create @
find . -maxdepth 1 ! -name '@' ! -name '.' -exec mv {} @/ \;

# Création des autres points de montage
btrfs subvolume create @home
btrfs subvolume create @log
btrfs subvolume create @cache
btrfs subvolume create @tmp

# Migration des données existantes vers les nouveaux sous-volumes
[ -d "@/home" ] && mv @/home/* @home/ 2>/dev/null
[ -d "@/var/log" ] && mv @/var/log/* @log/ 2>/dev/null
[ -d "@/var/cache" ] && mv @/var/cache/* @cache/ 2>/dev/null

# 2. Génération du fstab (propre et sans swap)
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
echo "🔧 Réinstallation de GRUB pour Btrfs..."
# Montage des systèmes de fichiers virtuels nécessaires à GRUB
for i in /dev /dev/pts /proc /sys /run; do mount -B $i @$i; done

# Exécution des commandes de réparation à l'intérieur du système
chroot @ /bin/bash <<CHROOT_EOF
grub-install /dev/sda
update-grub
CHROOT_EOF

# Nettoyage
for i in /run /sys /proc /dev/pts /dev; do umount @$i; done

echo "---"
echo "✅ Configuration terminée !"
echo "Tu peux maintenant démonter /target et redémarrer."
