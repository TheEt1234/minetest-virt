# Definitions
"Behaves like a unix named pipe" - this means that when you read it, it erases all the file's data

and i may use the terms "monitor" and "qmp" interchangeably

# Everything is in `virt`
- Special property of the `virt` table: the environment of any function in `virt` cannot be changed with setfenv

**`virt.machines`** - a table of all the QemuVirtMachines, indexed by their name  
**`virt.virtual_machines_location`** - the path to where all the virtual machines are located
**`virt.validate(string)`** - check if whatever you have is allowed in functions that use `os.execute` or `io.popen`, this returns a boolean

**`virt.create_image(name, size)`** - creates a virtual machine on the `virt.virtual_machines_location` (image + serial and qmp input/output files), `size` is in a qemu format, example: `1E` - 1 exabyte, `1G` - 1 gigabyte, `512k` - 512 kilobytes, `5M` - 5 megabytes

**`virt.create_image_from_base(name, base, resize)`** - copy the base image and optionally resize it by the amount given by `resize`, same format as before

**`virt.resize_image(name, size)`** - resizes an image, when shrinking, `--shrink` is enabled, this means all data loss in the image is finee


# class `virt.QemuVirtMachine`
- The Virtual machine manager
- `virt.QemuVirtMachine.new(name, info)` = `virt.QemuVirtMachine(name, info)`

**`QemuVirtMachine.new(name, info)`**  
- Creates a new QemuVirtMachine
- name: the name of the virtual machine
- info:
 - `info.nic` - a string or a boolean, if true, enables the internet for the virtual machine, if false, it disables it, if it's a string, custom configuration in the `-nic` option is allowed
 - `info.cdrom` - if provided it will use said path in the `-cdrom` option
 - `info.memory` - the amount of memory that the virtual machine receives, in qemu's format, so for example `512M` - 512 megabytes `5G` - 5 gigabytes

**`QemuVirtMachine:kill()`** - kills and closes all files opened of the virtual machine

**`bool = QemuVirtMachine:dead()`** - tells you if a QemuVirtMachine has been killed or if its alive

**`QemuVirtMachine:send_qmp_command(table)`** - sends a qemu qmp command, please read [the amazing qemu documentation](https://www.qemu.org/docs/master/interop/qemu-qmp-ref.html#qapidoc-1), the table is converted to json automatically  
**`table = QemuVirtMachine:receive_from_qmp()`** - gets the output of a qmp command, behaves like a unix named pipe  

**`QemuVirtMachine:send_input(input)`** - send normal (serial) input  
**`str = QemuVirtMachine:get_output()`** - receive the (serial) vm output, behaves like a unix named pipe

