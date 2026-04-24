#!/bin/bash

# --- Configuration ---
MOUNT_POINT="/mnt/btrfs_fix"
OPTIONS="noatime,compress=zstd:3,discard=async"

echo "🔍 Analyse du disque en cours..."

# 1. Détection dynamique de la partition Btrfs
DEV=$(blkid -t TYPE=btrfs -o device | head -n 1)
UUID=$(blkid -s UUID -o value "$DEV")

if [ -z "$DEV" ]; then
    echo "❌ Erreur : Aucune partition Btrfs n'a été trouvée. Vérifie ton installation."
    exit 1
fi

echo "📍 Cible détectée : $DEV"
echo "🆔 UUID : $UUID"

# 2. Préparation et Montage
sudo mkdir -p "$MOUNT_POINT"
sudo mount "$DEV" "$MOUNT_POINT"
cd "$MOUNT_POINT" || exit

# 3. Création des sous-volumes et migration
echo "📦 Structuration des sous-volumes (@, @home, @log, @cache, @tmp)..."

# Création du root subvolume et déplacement du système actuel dedans
if [ ! -d "@" ]; then
    sudo btrfs subvolume create @
    # On déplace tout vers @ sauf @ lui-même pour éviter une boucle
    sudo find . -maxdepth 1 ! -name '@' ! -name '.' -exec mv {} @/ \;
fi

# Création des sous-volumes secondaires
for sub in @home @log @cache @tmp; do
    [ ! -d "$sub" ] && sudo btrfs subvolume create "$sub"
done

# Déplacement des données existantes (pour garder tes réglages d'install)
[ -d "@/home" ] && sudo mv @/home/* @home/ 2>/dev/null
[ -d "@/var/log" ] && sudo mv @/var/log/* @log/ 2>/dev/null
[ -d "@/var/cache" ] && sudo mv @/var/cache/* @cache/ 2>/dev/null

# 4. Génération du nouveau fstab (écrase l'ancien pour être propre)
echo "📝 Réécriture de /etc/fstab..."
cat <<EOF | sudo tee @/etc/fstab
# /etc/fstab: static file system information.
UUID=$UUID /           btrfs $OPTIONS,subvol=@ 0 0
UUID=$UUID /home       btrfs $OPTIONS,subvol=@home 0 0
UUID=$UUID /var/log    btrfs $OPTIONS,subvol=@log 0 0
UUID=$UUID /var/cache  btrfs $OPTIONS,subvol=@cache 0 0
UUID=$UUID /tmp        btrfs $OPTIONS,subvol=@tmp 0 0
EOF

# 5. Réparation de GRUB via Chroot
echo "🔧 Réinstallation de GRUB pour éviter le mode Rescue..."
# Montage des systèmes de fichiers virtuels
for i in /dev /dev/pts /proc /sys /run; do sudo mount -B $i "@$i"; done

# On identifie le disque physique (ex: /dev/sda1 devient /dev/sda)
DISK=$(echo "$DEV" | sed 's/[0-9]*$//')

sudo chroot @ /bin/bash <<CHROOT_EOF
grub-install $DISK
update-grub
CHROOT_EOF

# 6. Nettoyage final
echo "🧹 Démontage et nettoyage..."
for i in /run /sys /proc /dev/pts /dev; do sudo umount "@$i"; done
cd /
sudo umount "$MOUNT_POINT"

echo "-------------------------------------------------------"
echo "✅ Configuration Btrfs terminée avec succès !"
echo "🚀 Tu peux maintenant redémarrer ton ordinateur."
