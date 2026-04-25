#!/bin/bash
# Script de migration Btrfs Sécurisé - Ubuntu 26.04
set -e

# --- [ CONFIGURATION ] ---
DEV_ROOT="/dev/sda1"
DEV_EFI="/dev/sda2"
MNT_ROOT="/mnt/btrfs_root"
MNT_SYS="/mnt/system_chroot"
OPTIONS="noatime,compress=zstd:3,discard=async"

# --- [ VÉRIFICATIONS DE SÉCURITÉ ] ---
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Erreur : Ce script doit être lancé avec sudo." ; exit 1
fi

if [ ! -b "$DEV_ROOT" ]; then
    echo "❌ Erreur : La partition $DEV_ROOT est introuvable." ; exit 1
fi

# Vérifier si on est bien en Live (on ne doit pas être sur sda1 comme racine)
if mount | grep " / " | grep -q "$DEV_ROOT"; then
    echo "❌ ERREUR CRITIQUE : Tu sembles avoir démarré sur le disque dur."
    echo "Tu DOIS lancer ce script depuis une session Live USB uniquement."
    exit 1
fi

echo "✅ Vérifications terminées. Début de l'opération..."

# --- [ 1/5 RÉCUPÉRATION DES UUID ] ---
UUID_ROOT=$(blkid -s UUID -o value $DEV_ROOT)
UUID_EFI=$(blkid -s UUID -o value $DEV_EFI)

# --- [ 2/5 CRÉATION DES SOUS-VOLUMES ] ---
mkdir -p $MNT_ROOT
mount -t btrfs -o subvolid=5 $DEV_ROOT $MNT_ROOT

echo "📦 Création des sous-volumes..."
for sub in @ @home @log @cache @tmp; do
    if [ ! -d "$MNT_ROOT/$sub" ]; then
        btrfs subvolume create "$MNT_ROOT/$sub"
    fi
done

# --- [ 3/5 MIGRATION DES DONNÉES ] ---
echo "🚚 Déplacement des fichiers (cette étape peut prendre du temps)..."
# On déplace tout ce qui n'est pas un sous-volume (commençant par @) vers @
find $MNT_ROOT -maxdepth 1 -not -name "@*" -not -name "." -not -name ".." -exec mv {} $MNT_ROOT/@/ \;

# Migration interne vers les sous-volumes dédiés
# On utilise rsync pour plus de sécurité lors du transfert interne si nécessaire, 
# mais mv est instantané sur le même filesystem Btrfs.
mv $MNT_ROOT/@/home/* $MNT_ROOT/@home/ 2>/dev/null || true
mv $MNT_ROOT/@/var/log/* $MNT_ROOT/@log/ 2>/dev/null || true
mv $MNT_ROOT/@/var/cache/* $MNT_ROOT/@cache/ 2>/dev/null || true
mv $MNT_ROOT/@/tmp/* $MNT_ROOT/@tmp/ 2>/dev/null || true

# --- [ 4/5 CONFIGURATION FSTAB ] ---
echo "📝 Mise à jour de /etc/fstab..."
cat <<EOF > $MNT_ROOT/@/etc/fstab
# /etc/fstab (Migration Btrfs)
UUID=$UUID_ROOT /               btrfs   defaults,subvol=@,$OPTIONS 0 1
UUID=$UUID_ROOT /home           btrfs   defaults,subvol=@home,$OPTIONS 0 2
UUID=$UUID_ROOT /var/log        btrfs   defaults,subvol=@log,$OPTIONS 0 2
UUID=$UUID_ROOT /var/cache      btrfs   defaults,subvol=@cache,$OPTIONS 0 2
UUID=$UUID_ROOT /tmp            btrfs   defaults,subvol=@tmp,$OPTIONS 0 2
UUID=$UUID_EFI  /boot/efi       vfat    defaults      0       1
EOF

# --- [ 5/5 MISE À JOUR DE GRUB (CHROOT) ] ---
echo "🔧 Mise à jour de GRUB..."
mkdir -p $MNT_SYS
mount -t btrfs -o subvol=@ $DEV_ROOT $MNT_SYS
mount $DEV_EFI $MNT_SYS/boot/efi

for i in /dev /dev/pts /proc /sys /run; do mount -B $i $MNT_SYS$i; done

# On force la réinstallation de GRUB pour être sûr qu'il cherche au bon endroit (@)
chroot $MNT_SYS /bin/bash -c "grub-install $DEV_ROOT && update-grub"

# --- [ NETTOYAGE ] ---
umount -R $MNT_SYS
umount $MNT_ROOT

echo "✨ Opération réussie ! Tu peux redémarrer."
