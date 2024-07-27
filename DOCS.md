# Definitions
**QMP** - the qemu monitor protocol, not to be confused with HMP (the usual meaning of "qemu monitor", human monitor protocol)  
**named pipe** - magic inter-process communication that has a name on your filesystem and your text editor *really* struggles with  
**virtual machine** - by this i mean the `x.img` file but also the named pipes (`x_something.in/.out`), but not the `vmname_pid` file  
**the pid file** - this is a file that contains the virtual machine's pid, only avaliable when it is actually running  
**size** - by this i mean qemu's size format, which is a string, example: `"3G"` - 3 gigabytes; `"256M"` - 256 megabytes

## Warning
All qemu IPC (inter-process communication) is handled with a named pipe (besides the temporary pid file)  
This means that when you read from them, the data is consumed, and the pipe gets emptied, so if you read it once, it's erased

also my docs may include weird typescriptey type definitions sometimes, beware of that

# `virt`
### Special properties:
- every function of the virt table cannot have its environment changed
### The stuffs inside:
**`virt.create_vm = function(name, size)`**   - creates a virtual machine

**`virt.create_vm_from_base = function(name, base, resize: number | nil)`**  - copies the base from the base_images folder to the virtual machines folder, creates the nessesary files, and resizes if needed

**`virt.resize_image = function(name, size)`** - resizes the image... also has the `--shrink` option which means that if theres any unfortunate data there, it will erase it

**`virt.delete_vm = function(name)`**   - deletes the vm and all of its other files

**`virt.machines`** - a table of all the virtual machines, indexed by name

# `virt.QemuVirtMachine`
### Special properties:
- same as virt
- its a class
- here it will be refered to as `QemuVirtMachine` instead of `virt.QemuVirtMachine`
### The insides:
####  **`vm, returned_existing = QemuVirtMachine.new(name, info: table)`**
- also can be **`QemuVirtMachine(name, info)`**
- makes a new `QemuVirtMachine` thingy
- info (almost all optional):
    - `info.memory` - a qemu size, this one is not optional
    - `info.nic` - if false, the virtual machine won't have access to the network, if true, it will have, if a string, you should see https://www.qemu.org/docs/master/system/invocation.html#hxtool-5, if nil the vm will still have networking
    - `info.cdrom` - choose a path for a cdrom
- the returned object (`vm`):
    - `vm.command` - the command that was used to launch qemu
    - `vm.info` - the info, but `info.vm_path` was added to refer to the base vm path
    - `vm.name` - the vm name
    - `vm.serial_input` - the serial input file
    - `vm.monitor_input` - the monitor input file
    - `vm.process` - the process popen pipe
    - `vm.qmp_greeting` - the qmp greeting, there is no documentation on it but basically its a table of the qemu version and stuff
    - *oh and also, qmp_capabilities has already been entered in for you, and yes, with no capabilities enabled*
- `returned_existing` - if there is a QemuVirtMachine inside `virt.machines` with the same name as is being launched, it will return that machine instead, ignoring all your `info`, 2 virtual machines with the same name cannot exist

**`QemuVirtMachine:kill()`** - kills the QemuVirtMachine based on pid in the pid file, and closes all files, if the pid file is missing it will just close all the files

**`bool = QemuVirtMachine:dead()`** - checks if a QemuVirtMachine has been killed, this is importarnt ***as the behaviour of QemuVirtmachine functions, when the QemuVirtMachine is dead, is undefined***

**`QemuVirtMachine:send_qmp_command(table)`** - send a qmp command to the vm, you can read the qmp docs [here, they are really boring](https://www.qemu.org/docs/master/interop/qemu-qmp-ref.html)

**`table = QemuVirtMachine:receive_from_qmp()`** - receives the output from qmp, if there are multiple responses, `minetest.parse_json` will most likely fail

**`table = QemuVirtMachine:send_qmp_and_receive_laggy_consider_not_using`** - send a qmp command, then receive the output, may sound simple but uh...... the source code speaks for itself:

```lua
function QemuVirtMachine:send_qmp_and_receive_laggy_consider_not_using(table)
    self:send_qmp_command(table)
    local out
    while out == nil do
        out = self:receive_from_qmp()
    end
    return out
end

```

**`QemuVirtMachine:send_input(input: string)`** - send a string to the virtual machine (thru serial)

**`QemuVirtMachine:get_output()`** - gets the serial output

**`QemuVirtMachine:send_keycombo(keycombo_array: array | string, hold_time: int | nil)`**
- this is a wrapper for the `send-key` qmp command
- hold_time is in miliseconds
- when hold_time is nil, the default is 100 miliseconds
- when a keycombo array is a string, it will split it by the `-` character into an array
- each key gets checked if its valid, if not it will silently not include it
- if every key is wrong or keycombo array is empty, it will return false

#### **Valid keys for QemuVirtMachine:send_keycombo(...)**
```
unmapped  
pause  
ro  
kp_comma  
kp_equals  
power  
hiragana  
henkan  
yen  
sleep  
wake  
audionext  
audioprev  
audiostop  
audioplay  
audiomute  
volumeup  
volumedown  
mediaselect  
mail  
calculator  
computer  
ac_home  
ac_back  
ac_forward  
ac_refresh  
ac_bookmarks  
muhenkan  
katakanahiragana  
lang1  
lang2  
f13  
f14  
f15  
f16  
f17  
f18  
f19  
f20  
f21  
f22  
f23  
f24  
shift  
shift_r  
alt  
alt_r  
ctrl  
ctrl_r  
menu  
esc  
1  
2  
3  
4  
5  
6  
7  
8  
9  
0  
minus  
equal  
backspace  
tab  
q  
w  
e  
r  
t  
y  
u  
i  
o  
p  
bracket_left  
bracket_right  
ret  
a  
s  
d  
f  
g  
h  
j  
k  
l  
semicolon  
apostrophe  
grave_accent  
backslash  
z  
x  
c  
v  
b  
n  
m  
comma  
dot  
slash  
asterisk  
spc  
caps_lock  
f1  
f2  
f3  
f4  
f5  
f6  
f7  
f8  
f9  
f10  
num_lock  
scroll_lock  
kp_divide  
kp_multiply  
kp_subtract  
kp_add  
kp_enter  
kp_decimal  
sysrq  
kp_0  
kp_1  
kp_2  
kp_3  
kp_4  
kp_5  
kp_6  
kp_7  
kp_8  
kp_9  
less  
f11  
f12  
print  
home  
pgup  
pgdn  
end  
left  
up  
down  
right  
insert  
delete  
stop  
again  
props  
undo  
front  
copy  
open  
paste  
find  
cut  
lf  
help  
meta_l  
meta_r  
compose  
```

#### **Example usage of QemuVirtMachine:send_keycombo(...)**
- `QemuVirtMachine:send_keycombo("ctrl-shift-c")`
- `QemuVirtMachine:send_keyombo({"ctrl","shift","c"}, 200)`
<hr>

**`QemuVirtMachine:send_human_monitor_command(command: str, cpu_index: int)`** - this is a wrapper for the `human-monitor-command` qmp command, see [*the docs*](https://www.qemu.org/docs/master/system/monitor.html) on how to use

**`QemuVirtMachine:powerdown()`** - a wrapper for the `system-powerdown` qmp command

**`QemuVirtMachine:pause()`** - a wrapper for the `stop` qmp command

**`QemuVirtMachine:resume()`** - a wrapper for the `cont` qmp command
