# Usage

Customize the script `build-initramfs.sh`. First, if needed, change the location variables at the beginning of the file:
- `INITRAMFS_DIR` (default: `/usr/src/initramfs`): controls where the initramfs content will be copied
- `INITRAMFS_CPIO` (default: `/usr/src/initramfs.cpio`): destination for the (uncompressed) cpio initramfs.
  This is the location to use in for the value of the `CONFIG_INITRAMFS_SOURCE` variable in the `.config` linux kernel config
- `INIT_SCRIPT` (default: `/root/init`): location of the init script

The current init script is configured to unlock the root partition. This needs to be reviewed for the setup.

Only the necessary firmwares for a given machine are copied. Review for the target machine.
It is possible to put more binaries in the initramfs, just copy those with the `copy` command.

# Credits

This script is based on a one given in
[Gentoo Wiki Custom_Initramfs/Examples](https://wiki.gentoo.org/wiki/Custom_Initramfs/Examples)
