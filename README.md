# Virt

*(A library for) Virtual machines (using qemu) in minetest!*

# Dependencies

- a linux system, ***this will not work on windows, i will make no attempt to support windows*** but if you want to contribute you absolutely can `(good luck...)`
- luajit FFI
- theese commands: `mkfifo`, `qemu_system-x86_64`, `qemu-img`, `timeout`, `cat` (yes the use of `timeout` and `cat` are as dumb as you think they are :>)
- trusted mod status

# Security

*this mod TRIES to not leak io.popen or os.execute*    
*but with lua that probably won't matter, because one can change out the many global functions that virt depends on and also there are like infinitely many ways to go about attacking it*  

***so make sure you trust all your mods to not abuse virt even if virt tries to not leak anything***

# Setup

- verify that you have all the dependancies
- give it the trusted mod status
- make/download at least one base image, base images are not included because *my internet isn't great..., and even then, i can't trust that yours will be good, the base image is just too big*

### Making your own base image (with arch linux)

1) create a qemu image
   - `qemu-img create -f qcow2 base_images/archlinux.img 2G`
2) Follow the [standard arch install guide](https://wiki.archlinux.org/title/Installation_guide) on the image
   - use `qemu-system-x86_64 -cpu host -enable-kvm -m 2G -cdrom <the arch iso> -drive file=base_images/archlinux.img -boot menu=on` to launch the virtual machine, or *whatever way you prefer*
3) Install a bootloader ***and make sure you include `console=ttyS0` in the kernel command line***
   - **when using grub**, before doing grub-mkconfig, go to `/etc/default/grub` and change `GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"` to `GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0"`, then run `grub-mkconfig -o /boot/grub/grub.cfg`
4) also make sure to have *nothing* graphical installed, and ***KEEP IT MINIMAL*** as the size of the base image is basically the minimum size for all images based on it (unless you want to risk data loss)
5) you can optionally do `/make_vm_from_base test archlinux 3G` and enable the example frontend (see first line of init.lua, and yes in the example frontend, the vm name is hardcoded to be `test`)

# Faq

Q: Why can't you just use the arch iso  
A: the arch linux iso does not have `console=ttyS0` in their kernel command line

Q: *How does it work*  
A: It uses named pipes (the .in/.out files) to communicate with qemu, it launches qemu with `io.popen` and kills it by seeing the pid in the pid file

Q: Why have rxi's json thingy when you can just use minetest's  
A: minetest's is weeird, when i try to do `minetest.write_json({a=5})` it returns `{"a":5.0}` when it should be `{"a":5}` and yes it matters for qemu
