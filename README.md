# Kalpa Driver Manager
KDialog based shell utility to install proprietary devices drivers on Kalpa Desktop.

# THIS SCRIPT IS ALPHA SOFTWARE AND NOT GUARANTEED TO WORK, PLEASE DO NOT USE IT EXCEPT YOU ARE A DEVELOPER

## How it works

Kalpa Driver Manager will analyse the underlying system and evaluate if it is eligable for any drivers supported by utiltiy.

## Supported drivers
- NVIDIA grapichs drivers (500 series or newer)
    * Maxwell, Pascal, Volta, Turing, Ampere, Ada Lovelace, Hopper, Blackwell micro architectures. (GTX 9xx, GTX 10, GTX 16, RTX 20, RTX 30, RTX 40, RTX 50) older architectures are detected and not supported. For any unknown NVIDIA GPU it will assume it to be a new GPU not yet known by Kalpa Driver Manager and try to install the latest driver series
    * Supports enrollment of MOK for SecureBoot systems if the closed source kernel module is required
    * Validates the installation on the next boot eg. if the required NVIDIA driver modules have been loaded

## Tested System configurations

### System A:
- CPU: AMD FX-8350
- GPU: NVIDIA GTX 970
- Boot: MBR, GRUB2, SecureBoot off
- Result: SUCCESS - Installed G06-closed and working

### System B:
- CPU: Intel i5-3230M
- GPU 0: HD 4000
- GPU 1: NVIDIA GT 730M
- BOOT: UEFI, systemd-boot, SecureBoot off
- Result: FAILED (expected) - Installation denied as GPU required G05 (490 driver series) which was expected. This driver series has limited Wayland support and regularly breaks on newer Kernel releases which in return will break the auto update of Kalpa for an undefined amount of time. Therefore Kepler (and older) GPUs are denied by the driver manager on purpose

### System C:
- CPU: AMD Ryzen 7 7800X3D
- GPU: NVIDIA RTX 3080
- Boot: UEFI, systemd-boot, SecureBoot on
- Result: SOFT-FAILED - Installed G06-open, MOK enrollment was not required for the open kernel module. However KWin was running on llvmpipe while the driver was successfully installed and loaded (according to nvidia-smi). See issue #2