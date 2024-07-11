local MP = minetest.get_modpath(minetest.get_current_modname())
local WP = minetest.get_worldpath()
virt = {
    machines = {},
    virtual_machines_location = MP .. "/virtual_machines", -- todo: change to world path
}
local function get_vm_path_from_name(name)
    return virt.location .. "/" .. name
end

local ie = assert(minetest.request_insecure_environment(),
    "this very much needs insecure environment, please add this mod to trusted mods")

-- FFI: import the kill function
local ffi = require("ffi")
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
local exec = ie.os.execute


-- YES this could've been bettter
-- but i don't care
local str_character_whitelist = "QWERTYUIOPASDFGHJKLZXCVBNMqwertyuiopasdfghjklzxcvbnmm1234567890/., " .. virt.location
local character_whitelist = {}

for i = 1, #str_character_whitelist do
    character_whitelist[sub(str_character_whitelist, i, i)] = true
end

local validate = function(something)
    for i = 1, #something do
        if not character_whitelist[sub(something, i, i)] then
            return false
        end
    end
    return true
end

virt.validate = validate -- make sure that the local validate cannot be tampered with


-- ok now the fun stuff
local function build_command(name, info)
    for k, v in pairs(info) do
        if type(v) ~= "string" or type(k) ~= "string" then
            error(tostring(k) .. " must be string!", 2)
        end
        assert(validate(v))
        info[k] = v
    end

    --[[
        shotout to anyone who understands what is below
    ]]
    local ret = gsub(gsub(format([[qemu-system-x86_64
 -name "%s"
 -cpu host
 -enable-kvm
 -smp 1
 -boot order=dc,menu=off
 -m "%s"
 -k en-us
 -drive file="%s"
 -nographic
 -nic %s
 -chardev file,id=serial,path="%s",input-path="%s"
 -chardev file,id=monitor,path="%s",input-path="%s"
 -serial chardev:serial
 -mon monitor,mode=control,pretty=off
 -watchdog-action poweroff
 -msg guest-name=on]],
        name, info.memory, info.drive_file, info.nic,
        info.serial_out_path, info.serial_in_path,
        info.monitor_out_path, info.monitor_in_path), "  ", " "), "\n", "")
    if info.cdrom then
        ret = ret .. format(" -cdrom %s", info.cdrom)
    end
    return ret
end

--[[
    The QemuVirtMachine class

    Basically allows you to manage a QemuVirtMachine
]]

local QemuVirtMachine = {}
virt.QemuVirtMachine = QemuVirtMachine

QemuVirtMachine.__index = QemuVirtMachine
QemuVirtMachine.new = function(name, info)
    if info.nic == false then info.nic = "none" end                   -- no networking
    if info.nic == nil or info.nic == true then info.nic = "user" end -- default networking
    info.drive_file = get_vm_path_from_name(name) .. ".img"

    info.serial_out_path = get_vm_path_from_name(name) .. "_serial_out.txt"
    info.serial_in_path = get_vm_path_from_name(name) .. "_serial_in.txt"

    info.monitor_out_path = get_vm_path_from_name(name) .. "_monitor_out.txt"
    info.monitor_in_path = get_vm_path_from_name(name) .. "_monitor_in.txt"


    if virt.machines[name] then
        virt.machines[name]:kill()
    end
    local vm = {
        command = build_command(name, info),
        info = info,
        name = name,
    }

    vm.serial = {
        inp = io.open(info.serial_in_path, "w+"),
        out = io.open(info.serial_out_path, "r+")
    }
    vm.monitor = {
        inp = io.open(info.monitor_in_path, "w+"),
        out = io.open(info.monitor_out_path, "r+"),
    }

    vm.process = ie.io.popen(vm.command)

    virt.machines[name] = vm
    return setmetatable(vm, QemuVirtMachine)
end

virt.create_image = function(name, size)
    assert(validate(name))
    assert(validate(size))
    exec(format("qemu-img create -f qcow2 '%s.img' '%s'", get_vm_path_from_name(name), size))
    ie.io.open(format("%s_serial_out.txt", get_vm_path_from_name(name)), "w+"):close()
    ie.io.open(format("%s_serial_in.txt", get_vm_path_from_name(name)), "w+"):close()
    ie.io.open(format("%s_monitor_out.txt", get_vm_path_from_name(name)), "w+"):close()
    ie.io.open(format("%s_monitor_in.txt", get_vm_path_from_name(name)), "w+"):close()
end

virt.create_image_from_base = function(name, base, resize)
    assert(validate(name))
    assert(validate(base))
    exec(format("cp '%s' '%s'", MP .. "/base_images/" .. base, get_vm_path_from_name(name)))
    ie.io.open(format("%s_serial_out.txt", get_vm_path_from_name(name)), "w+"):close()
    ie.io.open(format("%s_serial_in.txt", get_vm_path_from_name(name)), "w+"):close()
    ie.io.open(format("%s_monitor_out.txt", get_vm_path_from_name(name)), "w+"):close()
    ie.io.open(format("%s_monitor_in.txt", get_vm_path_from_name(name)), "w+"):close()
    if resize then
        virt.resize_image(name, size)
    end
end

virt.resize_image = function(name, size)
    if virt.machines[name] then
        minetest.log("error", "You shouldn't try to resize the vm when it is running, killing the vm, vm name:" .. name)
        virt.machines[name]:kill()
    end
    assert(validate(name))
    assert(validate(size))
    --[[
        When shrinking images, the --shrink option must be given.
        This informs qemu-img that the user acknowledges all loss of data beyond the truncated image’s end.
            - qemu docs

        In theory this shouldn't actually do anything bad like FORCE shrinking or idk
    ]]
    exec(format("qemu-img resize --shrink '%s.img' '%s'", get_vm_path_from_name(name), size))
end

virt.delete_vm = function(name)
    if virt.machines[name] then
        virt.machines[name]:kill()
    end

    ie.os.remove(get_vm_path_from_name(name) .. ".img")
    ie.os.remove(get_vm_path_from_name(name) .. "_serial_out.txt")
    ie.os.remove(get_vm_path_from_name(name) .. "_serial_in.txt")
    ie.os.remove(get_vm_path_from_name(name) .. "_monitor_out.txt")
    ie.os.remove(get_vm_path_from_name(name) .. "_monitor_in.txt")
end

function QemuVirtMachine:kill()
    local handle = assert(
        io.popen("pgrep -f '" .. string.gsub(self.command, "'", "\\'") .. "'"),
        "failed to kill vm\n" .. "name: " .. self.name .. "\ncommand: " .. self.command
    )
    local pid = handle:read("*a")
    kill(pid, SIGTERM)

    -- close the processes
    self.process:close()
    handle:close()

    -- close EVERYTHING
    self.monitor.inp:close()
    self.monitor.out:close()
    self.serial.inp:close()
    self.serial.out:close()
    virt.machines[self.name] = nil
end

function QemuVirtMachine:dead()
    return virt.machines[self.name] ~= self
end

-- monitor I/O
-- abstraction: uses tables instead of json
function QemuVirtMachine:send_to_monitor(table)
    local json = minetest.write_json(table)
    return self.monitor.inp:write(json)
end

function QemuVirtMachine:receive_from_monitor()
    local ret = self.monitor.out:read("*a")
    self.monitor.out:write("")
    return minetest.parse_json(ret)
end

-- serial I/O
function QemuVirtMachine:send_input(input)
    return self.serial.inp:write(input)
end

function QemuVirtMachine:get_output()
    local ret = self.serial.out:read("*a")
    self.serial.out:write("") -- behave like a pipe
    return ret
end

local old_setfenv = setfenv
local protected = {}

-- Now time for security
function env_lock(t, seen)
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
