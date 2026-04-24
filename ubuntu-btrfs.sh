#!/bin/bash

# Variables
TARGET="/target"
UUID="844149eb-3014-452d-bee0-4a5dc4d89a6a"
OPTIONS="noatime,compress=zstd:3,discard=async"

echo "--- Début de la restructuration Btrfs ---"

cd $TARGET

# 1. Création du sous-volume racine @ et déplacement des données
echo "Création du sous-volume @..."
btrfs subvolume create @
# On déplace tout le contenu actuel de /target vers @, sauf @ lui-même
find . -maxdepth 1 ! -name '@' ! -name '.' -exec mv {} @/ \;

# 2. Création des autres sous-volumes
echo "Création des autres sous-volumes (@home, @log, @cache, @tmp)..."
btrfs subvolume create @home
btrfs subvolume create @log
btrfs subvolume create @cache
btrfs subvolume create @tmp

# 3. Déplacement des données existantes (si présentes) dans les nouveaux sous-volumes
# On déplace le contenu de @/home vers @home, etc.
[ -d "@/home" ] && mv @/home/* @home/ 2>/dev/null
[ -d "@/var/log" ] && mv @/var/log/* @log/ 2>/dev/null
[ -d "@/var/cache" ] && mv @/var/cache/* @cache/ 2>/dev/null

# 4. Mise à jour du fichier fstab
echo "Génération du nouveau /etc/fstab..."
cat <<EOF > @/etc/fstab
# /etc/fstab: static file system information.
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=$UUID /           btrfs $OPTIONS,subvol=@ 0 0
UUID=$UUID /home       btrfs $OPTIONS,subvol=@home 0 0
UUID=$UUID /var/log    btrfs $OPTIONS,subvol=@log 0 0
UUID=$UUID /var/cache  btrfs $OPTIONS,subvol=@cache 0 0
UUID=$UUID /tmp        btrfs $OPTIONS,subvol=@tmp 0 0
EOF

echo "--- Configuration terminée avec succès ! ---"
echo "N'oubliez pas de démonter /target avant de redémarrer."
