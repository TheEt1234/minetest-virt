# Chatcommands
`/kill_all_vms` - kills all virtual machines  

`/make_vm_from_base <name> <base> [resize]` - makes a virtual machine, spaces in name and base aren't allowed, and ~~i am lazy to validate it all~~ with great power comes great responsibility so don't mispell your name or base or it may cause a server crash, also `'` can't be in any of theese fields, see definitions on what to put in the `[resize]` parameter

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

**`virt.json`** 
- `virt.json.encode`/`virt.json.decode`
- was done because of minor differences between minetest's json and how qemu expects it, like minetest json always has floats, qemu does not like that

# `virt.QemuVirtMachine`
### Special properties:
- same properties as virt
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

**`QemuVirtMachine:send_keycombo(keycombo: string)`**
- this is **not** a wrapper for the `send-key` qmp command because serial consoles don't support keyboards (or something)
- this does not send any sort of like.... real... input... or something.... it just sends ~~*funny invisible text that does something*~~ *really fancy ansi control characters*
- keys are seperated by `-`
- if it's a number inside (like `0xF-5`) it will interpret those numbers as characters with `string.char`
- supported thingys: `ctrl-<x>` (mostly-ish, see [this cool ascii table that has the funny ctrl-x things](https://ss64.com/ascii.html)), `del`, `ret`/`enter`, `backspace`/`bs`, `tab`, `null`
- anything else gets interpreted literally (as in `r-o-o-t` will get `root`)

#### **Example usage of QemuVirtMachine:send_keycombo(keycombo)**
- `QemuVirtMachine:send_keycombo("ctrl-C")`
<hr>

**`QemuVirtMachine:send_human_monitor_command(command: str, cpu_index: int)`** - this is a wrapper for the `human-monitor-command` qmp command, see [*the docs*](https://www.qemu.org/docs/master/system/monitor.html) on how to use

**`QemuVirtMachine:powerdown()`** - a wrapper for the `system-powerdown` qmp command

**`QemuVirtMachine:pause()`** - a wrapper for the `stop` qmp command

**`QemuVirtMachine:resume()`** - a wrapper for the `cont` qmp command


# `formspec = virt.make_terminal(text: string, position:table, settings:table)`
- the *extremely scuffed* ansi compliant-ish terminal
- adds a scrollbar looking thing too
- `position.x` `position.y` `position.w` `position.h` - the coordinates of the terminal in your formspec
- `position.size` - the size of the letter (multiplier) a good one is 0.3
- `position.scroll` - how much should the terminal be scrolled up (default 0, maximum scrolldown, the more up you go the more up the scroll gets, dont go to negative numbers)
- `settings.color` - the color scheme, [see this for 3-bit and 4-bit colors](https://en.wikipedia.org/wiki/ANSI_escape_code), it is a table from 0 to 15, ordered like wikipedia (sgr attributes 30 to 37 = 0 to 7; sgr attributes 90 to 97 = 7 to 15)

example of `settings.color`:  
```lua
local function rgb2hex(r, g, b)
    if not g then -- greyscale
        return "#" .. string.format("#%02X", r):rep(3)
    else
        return string.format("#%02X%02X%02X", r, g, b)
    end
end

return {
        [0] = rgb2hex(0, 0, 0),        -- black
        [1] = rgb2hex(170, 0, 0),      -- red
        [2] = rgb2hex(0, 170, 0),      -- green
        [3] = rgb2hex(170, 85, 0),     -- yellow
        [4] = rgb2hex(0, 0, 170),      -- blue
        [5] = rgb2hex(170, 0, 170),    -- magenta
        [6] = rgb2hex(0, 170, 170),    -- cyan
        [7] = rgb2hex(170, 170, 170),  -- white
        [8] = rgb2hex(85, 85, 85),     -- bright black
        [9] = rgb2hex(255, 85, 85),    -- bright red
        [10] = rgb2hex(85, 255, 85),   -- bright green
        [11] = rgb2hex(255, 255, 85),  -- bright yellow
        [12] = rgb2hex(85, 85, 255),   -- bright blue
        [13] = rgb2hex(255, 85, 255),  -- bright magenta
        [14] = rgb2hex(85, 255, 255),  -- bright cyan
        [15] = rgb2hex(255, 255, 255), -- bright white
    }
```


# extra docs for `virt.make_terminal`'s text

- the terminal only supports ascii
- control characters get ignored
- see [the wikipedia page for ansi escape codes :D :D :D :D that's what this was based off of](https://en.wikipedia.org/wiki/ANSI_escape_code) before reading

### C0 escape codes

- backspace (0x08) - erases the character and goes back
- tab (0x09) - unchanged
- line feed (0x0A) (also known as \n) - moves to next line and like does the thing you expect from \n in unix (not windows basically)
- carriage return (0x0D) - unchanged
- escape (0x1B) - this is where the shenanigans begin

### CSI escape codes

- most of them are implemented
- specifically the commands/final bytes:
  - `A`, `B`, `C`, `D`, `E`, `F`, `G`, `H`, `J`, `K`, `S`, `T`, `f`, (`m` -  partial), `s`, `u`

### SGR parameters

- a decent amount (for minetest) is supported
- i know *all* of them could be supported but i am lazy :>
- theese are supported:
  - `0`, `1`, `3`, `7`, `8`, `10`, `22`, `23`, `28`, `30 to 37`, `90 to 97`, `38`, `39`, `40 to 47`, `100 to 107`, `48`, `49`
