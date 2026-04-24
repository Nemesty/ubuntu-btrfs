#!/bin/bash
# Script de création de sous-volumes Btrfs (Ubuntu, en français)

set -e

# Vérifie qu'on est root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ ERREUR : ce script doit être exécuté en root." >&2
    exit 1
fi

ROOT_DEV="/dev/sda1"
BOOT_DEV="/dev/sda2"
# /dev/sda1 : partition Btrfs racine ; /dev/sda2 : partition /boot (grub)

# Vérification des périphériques
if [ ! -b "$ROOT_DEV" ]; then
    echo "❌ ERREUR : périphérique $ROOT_DEV introuvable." >&2
    exit 1
fi
if [ ! -b "$BOOT_DEV" ]; then
    echo "❌ ERREUR : périphérique $BOOT_DEV introuvable." >&2
    exit 1
fi

# Détecte si /dev/sda1 est déjà monté : on récupère son point de montage si existant
MNT=""
MNT_DETECT=$(findmnt -nr -o TARGET -S "$ROOT_DEV")
if [ -n "$MNT_DETECT" ]; then
    MNT="$MNT_DETECT"
    echo "ℹ️  Le périphérique $ROOT_DEV est déjà monté sur $MNT."
else
    # Monte sur /mnt par défaut
    MNT="/mnt"
    mkdir -p "$MNT"
    echo "🔧 Montage de $ROOT_DEV sur $MNT..."
    if ! mount "$ROOT_DEV" "$MNT"; then
        echo "❌ ERREUR : impossible de monter $ROOT_DEV sur $MNT." >&2
        exit 1
    fi
fi

# Crée un snapshot de la racine actuelle sous le nom @
echo "📌 Création du sous-volume racine \`@\` (snapshot)..."
if ! btrfs subvolume snapshot "$MNT" "$MNT/@"; then
    echo "❌ ERREUR : échec du snapshot @." >&2
    exit 1
fi

# Crée les sous-volumes @home, @log, @cache, @tmp
echo "📁 Création des autres sous-volumes : @home, @log, @cache, @tmp..."
for SUB in "@home" "@log" "@cache" "@tmp"; do
    if btrfs subvolume create "$MNT/$SUB" 2>/dev/null; then
        echo " - $SUB créé."
    else
        echo "ℹ️  $SUB existant, on passe."  # si déjà créé
    fi
done

# Déplace le contenu de /var/log et /var/cache dans les sous-volumes correspondants,
# seulement si ces dossiers existent et ne sont pas des points de montage distincts.
if [ -d "$MNT/var/log" ] && ! mountpoint -q "$MNT/var/log"; then
    echo "🔄 Déplacement du contenu de /var/log vers le sous-vol @log..."
    mv "$MNT/var/log/"* "$MNT/@log/" 2>/dev/null || true
fi
if [ -d "$MNT/var/cache" ] && ! mountpoint -q "$MNT/var/cache"; then
    echo "🔄 Déplacement du contenu de /var/cache vers le sous-vol @cache..."
    mv "$MNT/var/cache/"* "$MNT/@cache/" 2>/dev/null || true
fi

# Nettoyage temporaire : on ne touche pas aux dossiers déjà montés
echo "🧹 Nettoyage des anciens fichiers hors sous-volumes..."
shopt -s extglob
for ENTRY in "$MNT"/*; do
    NAME=$(basename "$ENTRY")
    # On conserve le dossier . (point de montage), @* (sous-vols), /var
    if [[ "$NAME" != "@"* && "$NAME" != "var" && "$NAME" != "." ]]; then
        if mountpoint -q "$ENTRY"; then
            echo "   * $NAME est monté, on ne le supprime pas."
        else
            rm -rf "$ENTRY"
            echo "   - Suppression de $NAME"
        fi
    fi
done
shopt -u extglob

# Monte à nouveau le root sur le sous-volume @ pour la suite
echo "🔄 Remontage de la racine sur le subvol @..."
umount "$MNT"
if ! mount -o subvol=@ "$ROOT_DEV" "$MNT"; then
    echo "❌ ERREUR : échec du remontage de $ROOT_DEV avec subvol=@" >&2
    exit 1
fi

# Sauvegarde /etc/fstab existant et modification pour ajouter les sous-volumes
FSTAB="$MNT/etc/fstab"
echo "💾 Sauvegarde de $FSTAB en $FSTAB.bak..."
cp "$FSTAB" "$FSTAB.bak"

echo "✏️  Mise à jour de /etc/fstab (options Btrfs)..."
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")
# Enlève les anciennes lignes btrfs pour éviter les doublons
sed -i "/UUID=$ROOT_UUID.* btrfs/d" "$FSTAB"

# Ajout des nouvelles lignes pour les subvolumes racine, home, log, cache, tmp
cat <<EOF >> "$FSTAB"
# Sous-volumes Btrfs pour /dev/sda1
UUID=$ROOT_UUID /       btrfs rw,noatime,discard=async,compress=zstd:3,subvol=@      0 1
UUID=$ROOT_UUID /home   btrfs rw,noatime,discard=async,compress=zstd:3,subvol=@home  0 2
UUID=$ROOT_UUID /var/log btrfs rw,noatime,discard=async,compress=zstd:3,subvol=@log 0 2
UUID=$ROOT_UUID /var/cache btrfs rw,noatime,discard=async,compress=zstd:3,subvol=@cache 0 2
UUID=$ROOT_UUID /tmp    btrfs rw,noatime,discard=async,compress=zstd:3,subvol=@tmp   0 2
EOF

# Monte /dev/sda2 sur /boot pour mettre à jour grub
echo "🔧 Montage de $BOOT_DEV sur $MNT/boot..."
mkdir -p "$MNT/boot"
if ! mount "$BOOT_DEV" "$MNT/boot"; then
    echo "❌ ERREUR : impossible de monter $BOOT_DEV sur $MNT/boot." >&2
    exit 1
fi

# Prépare le chroot : bind /proc, /sys, /dev, /run
for D in proc sys dev run; do
    mount --bind "/$D" "$MNT/$D"
done

# Mets à jour grub et l'initramfs dans le chroot
echo "🔄 Chroot et mise à jour de GRUB/initramfs..."
chroot "$MNT" update-grub
chroot "$MNT" update-initramfs -u

# Démontage final propre
echo "🧹 Démontage des systèmes montés..."
for D in proc sys dev run; do
    umount "$MNT/$D" 2>/dev/null || true
done
umount "$MNT/boot" 2>/dev/null || true
umount "$MNT" 2>/dev/null || true

echo "✅ Script terminé avec succès !"
echo "ℹ️  Redémarrez le système avant d’installer Snapper ou autre gestionnaire de snapshots."
