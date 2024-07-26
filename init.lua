-- this code may look nightmarish but... well... if you think that don't look at term.lua
local cat_timeout = "0.01s"

local MP = minetest.get_modpath(minetest.get_current_modname())
local WP = minetest.get_worldpath()
virt = {
    machines = {},
    virtual_machines_location = MP .. "/virtual_machines", -- todo: change to world path
}

local function get_vm_file_path_from_name(name)
    return virt.virtual_machines_location .. "/" .. name
end

local ie = assert(minetest.request_insecure_environment(),
    "this very much needs insecure environment, please add this mod to trusted mods")

-- FFI: import the kill function
local ffi = ie.require("ffi")
ffi.cdef [[
    int kill(int pid, int sig);
]]

local kill = ffi.C.kill
local SIGTERM = 15 -- im not sure what all the SIG's do so i just chose the most serious looking one
-- i imagine a kernel ordered terminator comes to the process and terminates it


-- i define theese in ie.* because an untrusted mod could overwrite them
local format = ie.string.format
local gsub = ie.string.gsub
local sub = ie.string.sub
local find = ie.string.find
local exec = ie.os.execute

local function validate_bash_str(str)
    return not (find(str, "'") or find(str, "%c"))
end

local function mkfifo(file)
    assert(validate_bash_str(file))
    exec(format("mkfifo '%s.in' '%s.out'", file))
end

local function validate_qemu_size(str)
    local number = tonumber(sub(str, 1, -2))
    local suffix = sub(str, -1, -1)

    if number == nil or number < 0 or (math.floor(number) ~= number) then return false end
    if suffix == "k" or suffix == "M" or suffix == "G" or suffix == "G" or suffix == "G" or suffix == "T" or suffix == "P" or suffix == "E" then
        -- if you need the P or E suffix you have a problem
        return true
    else
        return false
    end
end


virt.create_image = function(name, size)
    assert(validate_bash_str(name))
    assert(validate_qemu_size(size))

    local vm_path = get_vm_file_path_from_name(name)

    exec(format("qemu-img create -f qcow2 '%s.img' '%s'", vm_path, size))
    mkfifo(vm_path .. "_serial")
    mkfifo(vm_path .. "_monitor")
end

virt.create_image_from_base = function(name, base, resize)
    assert(validate_bash_str(base))
    assert(validate_bash_str(name))
    assert(validate_qemu_size(resize))
    local vm_path = get_vm_file_path_from_name(name)

    exec(format("cp '%s.img' '%s.img'", (MP .. "/base_images/" .. base), vm_path))
    mkfifo(vm_path .. "_serial")
    mkfifo(vm_path .. "_monitor")

    if resize then
        virt.resize_image(name, resize)
    end
end

virt.resize_image = function(name, size)
    assert(validate_bash_str(name))
    assert(validate_qemu_size(size))

    if virt.machines[name] then
        minetest.log("error", "You shouldn't try to resize the vm when it is running, killing the vm, vm name:" .. name)
        virt.machines[name]:kill()
    end

    --[[
        When shrinking images, the --shrink option must be given.
        This informs qemu-img that the user acknowledges all loss of data beyond the truncated image’s end.
            - qemu docs
    ]]

    exec(format("qemu-img resize --shrink '%s.img' '%s'", get_vm_file_path_from_name(name), size))
end

virt.delete_vm = function(name)
    assert(validate_bash_str(name))

    if virt.machines[name] then
        virt.machines[name]:kill()
    end

    ie.os.remove(get_vm_file_path_from_name(name) .. ".img")
    ie.os.remove(get_vm_file_path_from_name(name) .. "_serial.out")
    ie.os.remove(get_vm_file_path_from_name(name) .. "_serial.in")
    ie.os.remove(get_vm_file_path_from_name(name) .. "_monitor.out")
    ie.os.remove(get_vm_file_path_from_name(name) .. "_monitor.in")
end

-- ok now the fun stuff
local function build_command(name, info)
    for k, v in pairs(info) do
        if type(v) ~= "string" or type(k) ~= "string" then
            error(tostring(k) .. " must be string!", 2)
        end
        assert(validate_bash_str(v))
        info[k] = v
    end

    local ret = gsub(format([[qemu-system-x86_64
 -name '%s'
 -cpu host
 -enable-kvm
 -smp 1
 -boot order=dc,menu=off
 -m '%s'
 -k en-us
 -drive file='%s.img'
 -nographic
 -nic '%s'
 -chardev pipe,id=serial,path='%s_serial'
 -chardev pipe,id=monitor,path='%s_monitor'
 -serial chardev:serial
 -mon monitor,mode=control,pretty=off
 -watchdog-action poweroff
 -msg guest-name=on
 -pidfile '%s_pid']],
        name, info.memory, info.vm_path, info.nic, info.vm_path, info.vm_path, info.vm_path), "\n", "")
    if info.cdrom then
        ret = ret .. format(" -cdrom '%s'", info.cdrom)
    end
    return ret
end

--[[
    The QemuVirtMachine class
    You know what this does
]]

local QemuVirtMachine = {}
virt.QemuVirtMachine = QemuVirtMachine
QemuVirtMachine.__index = QemuVirtMachine
QemuVirtMachine.new = function(name, info)
    assert(validate_bash_str(name))

    if virt.machines[name] then
        return virt.machines[name], false
    end

    if info.nic == false then info.nic = "none" end                   -- no networking
    if info.nic == nil or info.nic == true then info.nic = "user" end -- default networking

    info.vm_path = get_vm_file_path_from_name(name)

    local vm = {
        command = build_command(name, info),
        info = info,
        name = name,
    }


    vm.serial_input = ie.io.open(info.vm_path .. "_serial.in", "w+")
    vm.monitor_input = ie.io.open(info.vm_path .. "_monitor.in", "w+")

    minetest.log("[virt] Launching a virtual machine with command: " .. vm.command)
    vm.process = ie.io.popen(vm.command)

    virt.machines[name] = vm
    setmetatable(vm, QemuVirtMachine)

    vm.qmp_greeting = QemuVirtMachine.receive_from_qmp(vm)

    QemuVirtMachine.send_qmp_and_receive_laggy_consider_not_using(vm, {
        execute = "qmp_capabilities" -- enter command mode or whatever, basically just make it work lmfao
    })
    return vm
end

setmetatable(QemuVirtMachine, { __call = QemuVirtMachine.new })

function QemuVirtMachine:kill()
    local file = ie.io.open(self.vm_path .. "_pid", "r") -- a temporary file
    -- if nil, it most likely means it has been killed already
    if file ~= nil then
        local pid = tonumber(file:read("*a"))
        file:close()

        kill(pid, SIGTERM)
    end

    -- close the process pipe
    self.process:close()

    -- close EVERYTHING
    self.monitor_input:close()
    self.serial_input:close()
    virt.machines[self.name] = nil
end

function QemuVirtMachine:dead()
    if not ie.io.open(self.vm_path .. "_pid", "r") then -- if the pid file is not present, it's dead
        self:kill()
        return true
    end
    return virt.machines[self.name] ~= self
end

function QemuVirtMachine:revive()
    return virt.machines[self.name] or QemuVirtMachine.new(self.name, self.info)
end

-- monitor I/O

-- abstraction: uses tables instead of json

function QemuVirtMachine:send_qmp_command(table)
    local json = minetest.write_json(table)
    return self.monitor_input:write(json)
end

function QemuVirtMachine:receive_from_qmp()
    local proc = io.popen("timeout " .. cat_timeout .. " cat " .. self.vm_path .. "_monitor.out", "r")
    local ret = proc:read("*a")
    proc:close()

    return minetest.parse_json(ret)
end

-- consider not using....
-- but i understand if its the only reliable way
function QemuVirtMachine:send_qmp_and_receive_laggy_consider_not_using(table)
    self:send_qmp_command(table)
    local out = ""
    while #out == 0 do
        out = self:receive_from_qmp()
    end

    return minetest.parse_json(out)
end

-- serial I/O
-- \n is enter btw
function QemuVirtMachine:send_input(input)
    return self.serial_input:write(input)
end

function QemuVirtMachine:get_output()
    local proc = io.popen("timeout " .. cat_timeout .. " cat " .. self.vm_path .. "_serial.out", "r")
    local ret = proc:read("*a")
    proc:close()

    return ret
end

-- QMP command wrappers

local valid_keycodes = {
    ["unmapped"] = true,
    ["pause"] = true,
    ["ro"] = true,
    ["kp_comma"] = true,
    ["kp_equals"] = true,
    ["power"] = true,
    ["hiragana"] = true,
    ["henkan"] = true,
    ["yen"] = true,
    ["sleep"] = true,
    ["wake"] = true,
    ["audionext"] = true,
    ["audioprev"] = true,
    ["audiostop"] = true,
    ["audioplay"] = true,
    ["audiomute"] = true,
    ["volumeup"] = true,
    ["volumedown"] = true,
    ["mediaselect"] = true,
    ["mail"] = true,
    ["calculator"] = true,
    ["computer"] = true,
    ["ac_home"] = true,
    ["ac_back"] = true,
    ["ac_forward"] = true,
    ["ac_refresh"] = true,
    ["ac_bookmarks"] = true,
    ["muhenkan"] = true,
    ["katakanahiragana"] = true,
    ["lang1"] = true,
    ["lang2"] = true,
    ["f13"] = true,
    ["f14"] = true,
    ["f15"] = true,
    ["f16"] = true,
    ["f17"] = true,
    ["f18"] = true,
    ["f19"] = true,
    ["f20"] = true,
    ["f21"] = true,
    ["f22"] = true,
    ["f23"] = true,
    ["f24"] = true,
    ["shift"] = true,
    ["shift_r"] = true,
    ["alt"] = true,
    ["alt_r"] = true,
    ["ctrl"] = true,
    ["ctrl_r"] = true,
    ["menu"] = true,
    ["esc"] = true,
    ["1"] = true,
    ["2"] = true,
    ["3"] = true,
    ["4"] = true,
    ["5"] = true,
    ["6"] = true,
    ["7"] = true,
    ["8"] = true,
    ["9"] = true,
    ["0"] = true,
    ["minus"] = true,
    ["equal"] = true,
    ["backspace"] = true,
    ["tab"] = true,
    ["q"] = true,
    ["w"] = true,
    ["e"] = true,
    ["r"] = true,
    ["t"] = true,
    ["y"] = true,
    ["u"] = true,
    ["i"] = true,
    ["o"] = true,
    ["p"] = true,
    ["bracket_left"] = true,
    ["bracket_right"] = true,
    ["ret"] = true,
    ["a"] = true,
    ["s"] = true,
    ["d"] = true,
    ["f"] = true,
    ["g"] = true,
    ["h"] = true,
    ["j"] = true,
    ["k"] = true,
    ["l"] = true,
    ["semicolon"] = true,
    ["apostrophe"] = true,
    ["grave_accent"] = true,
    ["backslash"] = true,
    ["z"] = true,
    ["x"] = true,
    ["c"] = true,
    ["v"] = true,
    ["b"] = true,
    ["n"] = true,
    ["m"] = true,
    ["comma"] = true,
    ["dot"] = true,
    ["slash"] = true,
    ["asterisk"] = true,
    ["spc"] = true,
    ["caps_lock"] = true,
    ["f1"] = true,
    ["f2"] = true,
    ["f3"] = true,
    ["f4"] = true,
    ["f5"] = true,
    ["f6"] = true,
    ["f7"] = true,
    ["f8"] = true,
    ["f9"] = true,
    ["f10"] = true,
    ["num_lock"] = true,
    ["scroll_lock"] = true,
    ["kp_divide"] = true,
    ["kp_multiply"] = true,
    ["kp_subtract"] = true,
    ["kp_add"] = true,
    ["kp_enter"] = true,
    ["kp_decimal"] = true,
    ["sysrq"] = true,
    ["kp_0"] = true,
    ["kp_1"] = true,
    ["kp_2"] = true,
    ["kp_3"] = true,
    ["kp_4"] = true,
    ["kp_5"] = true,
    ["kp_6"] = true,
    ["kp_7"] = true,
    ["kp_8"] = true,
    ["kp_9"] = true,
    ["less"] = true,
    ["f11"] = true,
    ["f12"] = true,
    ["print"] = true,
    ["home"] = true,
    ["pgup"] = true,
    ["pgdn"] = true,
    ["end"] = true,
    ["left"] = true,
    ["up"] = true,
    ["down"] = true,
    ["right"] = true,
    ["insert"] = true,
    ["delete"] = true,
    ["stop"] = true,
    ["again"] = true,
    ["props"] = true,
    ["undo"] = true,
    ["front"] = true,
    ["copy"] = true,
    ["open"] = true,
    ["paste"] = true,
    ["find"] = true,
    ["cut"] = true,
    ["lf"] = true,
    ["help"] = true,
    ["meta_l"] = true,
    ["meta_r"] = true,
    ["compose"] = true,
}
--[[
    keycombo_array: can be a string of valid_keycodes, or a string seperated by "-", that upon seperation, will have valid keycodes
    hold_time is in miliseconds, and is optional, by default 100 miliseconds
]]
function QemuVirtMachine:send_keycombo(keycombo_array, hold_time)
    if type(keycombo_array) == "string" then
        keycombo_array = string.split(keycombo_array, "-")
    end
    if not hold_time then hold_time = 100 end
    local keys = {}

    for _, v in ipairs(keycombo_array) do
        if valid_keycodes[v] then
            keys[#keys + 1] = {
                type = "qcode",
                data = v,
            }
        end
    end
    QemuVirtMachine:send_qmp_command({
        execute = "send-key",
        arguments = {
            keys = keys,
            hold_time = hold_time
        }
    })
end

local function make_function_for(cmd, alias)
    QemuVirtMachine[alias or cmd] = function(self)
        self:send_qmp_command({
            execute = cmd
        })
    end
end

-- https://www.qemu.org/docs/master/system/monitor.html#qemu-monitor
-- command_line: string
-- cpu_index: int (optional)

function QemuVirtMachine:send_human_monitor_command(command_line, cpu_index)
    return self:send_qmp_and_receive_promise_laggy_consider_not_using({
        execute = "human-monitor-command",
        ["command-line"] = command_line,
        ["cpu-index"] = cpu_index,
    })
end

make_function_for("system-powerdown")
make_function_for("stop", "pause")
make_function_for("cont", "resume")


local old_setfenv = setfenv
local protected = {}

-- Now time for security
function env_lock(t, seen)
    if seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
        if type(v) == "table" and not seen[v] then
            env_lock(t, seen)
        end
        if type(v) == "function" then
            -- we need to somehow detect setfenv tampering
            protected[v] = true
        end
    end
end

env_lock(virt, {})

-- attempt to secure virt just a bit
function setfenv(f, ...)
    if protected[f] then error("virt: no you can't modify the environment of a virt.* function") end
    old_setfenv(f, ...)
end

protected[setfenv] = true

minetest.register_on_shutdown(function()
    for k, v in pairs(virt.machines) do
        v:kill()
    end
end)

dofile(MP .. "/term.lua")
