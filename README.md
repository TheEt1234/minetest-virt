do you not like luacontrollers, or joe's vm16? do you want something more *real*-ish?
i've got a solution!

# Virt

Virtual machines in minetest!

*Can it be done? Yes. Should it be done? No.*

*a really weird really high level qemu wrapper desgined for minetest*  
*maybeee just maybe deserves the complex installation tag*

# Dependencies

- a linux system, ***this will not work on windows, i will make no attempt to support windows*** but heyyy if you want to contribute you absolutely can `(good luck...)`
- luajit FFI
- theese commands: `qemu_system-x86_64`, `qemu-img`, `timeout`, `cat` (yes the use of `timeout` and `cat` are as dumb as you think they are :>)
- trusted mod status and read/write access to the world folder and mod folder

# Security

*this mod TRIES to not leak io.popen or os.execute*    
*but with lua that probably won't matter, because one can change out the many global functions that virt depends on and also there are like infinitely many ways to go about attacking it*  

***so make sure you trust all your mods to not abuse virt even if virt tries to not leak anything***

# Setup
- verify that you have all the dependancies
- give it the trusted mod status
- make at least one base image, base images are not shipped because *my internet is dogwater, and yours is most likely too, the base image will be way too big*
### Making your own base image (arch linux)
1) create a qemu image
   - `qemu-img create -f qcow2 base_images/archlinux.img 2G`
2) Follow the [standard arch install guide](https://wiki.archlinux.org/title/Installation_guide) on the image
   - use `qemu-system-x86_64 -cpu host -enable-kvm -m 2G -cdrom <the arch iso> -drive file=base_images/archlinux.img -boot menu=on` to launch the virtual machine, or whatever way you prefer
3) Install a bootloader ***and make sure you include`console=ttyS0` in the kernel command line***
   - **when using grub**, before doing grub-mkconfig, go to `/etc/default/grub` and change `GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"` to `GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0"`, then run `grub-mkconfig -o /boot/grub/grub.cfg`
4) also make sure to have *nothing* graphical installed, and ***KEEP IT MINIMAL*** as the size of the base image is basically the minimum size for all images based on it (unless you want to risk data loss)
5) you are basically done with the installation

# Faq

Q: "Why can't you just use the arch iso"  
A: the arch linux iso does not have `console=ttyS0` in their kernel command line


