do you not like luacontrollers, or joe's vm16? do you want something more *real*-ish?
i've got a solution!

# Virt

*a successor to my minetest-qemu project*

*a really weird really high level qemu wrapper desgined for minetest*  
*maybeee just maybe deserves the complex installation tag*
# Dependencies

- a linux system, ***this will not work on windows, i will make no attempt to support windows*** but heyyy if you want to contribute you absolutely can
- theese commands: `qemu_system-x86_64`, `qemu-img`, `pgrep`
- trusted mod status and read/write access to the world folder and mod folder

# Security

*this mod TRIES to not leak io.popen or os.execute*    
*but with lua that probably won't matter, because one can change out the many global functions that virt depends on*  

***so make sure you trust all your mods to not abuse virt***

# Setup
- verify that you have the dependancies
- install the mod (it can take an extremely long time depending on your connection because of the base image, i recomend not installing from minetest directly so that you can track the progress)
- give it the trusted mod status
- you are done

# Notes
- qemu is complex magic and i hate it and i love it
- qemu is actually kinda simple to use
- qemu
- i couldn't figure out what libvirt was
- don't use btrfs it's dogwater on qcow, at least thats what the docs say