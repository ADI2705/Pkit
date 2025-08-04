 #!/bin/bash

IPMICFG_SRC="/home/test/servertest/IPMICFG-Linux.x86_64"
IPMICFG_DEST="/usr/local/bin/ipmicfg"

# Check if the source exists
if [ ! -f "$IPMICFG_SRC" ]; then
    echo "[IPMICFG INSTALL] ERROR: $IPMICFG_SRC not found."
    exit 1
fi

# Make it executable
chmod +x "$IPMICFG_SRC"
echo "[IPMICFG INSTALL] Made $IPMICFG_SRC executable."

# Create symlink if not already present
if [ -L "$IPMICFG_DEST" ] || [ -e "$IPMICFG_DEST" ]; then
    echo "[IPMICFG INSTALL] Symlink or file already exists at $IPMICFG_DEST."
else
    ln -s "$IPMICFG_SRC" "$IPMICFG_DEST"
    echo "[IPMICFG INSTALL] Symlink created: $IPMICFG_DEST -> $IPMICFG_SRC"
fi

echo "[IPMICFG INSTALL] You can now run 'ipmicfg' from anywhere."
