#!/bin/bash

# Define variables
APPIMAGE_URL="https://github.com/TheTumultuousUnicornOfDarkness/CPU-X/releases/download/5.3.1/CPU-X-5.3.1-x86_64.AppImage"
APPIMAGE_NAME="CPU-X-5.3.1-x86_64.AppImage"
INSTALL_PATH="."
SYMLINK="/usr/bin/cpu-x"

# Log start
echo "[CPU-X INSTALL] Starting CPU-X installation script."

# Download AppImage
echo "[CPU-X INSTALL] Downloading CPU-X AppImage from $APPIMAGE_URL..."
wget -q --show-progress "$APPIMAGE_URL" -O "$INSTALL_PATH/$APPIMAGE_NAME"

# Make it executable
echo "[CPU-X INSTALL] Making AppImage executable..."
chmod +x "$INSTALL_PATH/$APPIMAGE_NAME"

# Remove old symlink if exists
if [ -L "$SYMLINK" ]; then
    echo "[CPU-X INSTALL] Removing old symlink at $SYMLINK..."
    rm -f "$SYMLINK"
fi

# Create new symlink
echo "[CPU-X INSTALL] Creating new symlink at $SYMLINK..."
ln -s "$INSTALL_PATH/$APPIMAGE_NAME" "$SYMLINK"

# Confirm
echo "[CPU-X INSTALL] CPU-X installed successfully!"
echo "[CPU-X INSTALL] Run: cpu-x --cli   (TUI)"
echo "[CPU-X INSTALL] Run: cpu-x --dump  (dump hardware info)"
