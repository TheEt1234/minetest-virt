local load_example_frontend = true

-- this code may look nightmarish but... well... if you think that don't look at term.lua
local cat_timeout = "0.001s"

local MP = minetest.get_modpath(minetest.get_current_modname())
local WP = minetest.get_worldpath()

virt = {
    machines = {},
    virtual_machines_location = WP .. "/virtual_machines", -- todo: change to world path
    json = loadfile(MP .. "/json.lua")()
}

minetest.mkdir(virt.virtual_machines_location)

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
    exec(format("mkfifo '%s.in' '%s.out'", file, file))
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


virt.create_vm = function(name, size)
    assert(validate_bash_str(name))
    assert(validate_qemu_size(size))

    local vm_path = get_vm_file_path_from_name(name)

    exec(format("qemu-img create -f qcow2 '%s.img' '%s'", vm_path, size))
    mkfifo(vm_path .. "_serial")
    mkfifo(vm_path .. "_monitor")
end

virt.create_vm_from_base = function(name, base, resize)
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
 -pidfile '%s_pid']], name, info.memory, info.vm_path, info.nic, info.vm_path, info.vm_path, info.vm_path), "\n", "")
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
        return virt.machines[name], true
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

    minetest.log("action", "[virt] Launching a virtual machine with command: " .. vm.command)
    vm.process = ie.io.popen(vm.command)

    virt.machines[name] = vm
    setmetatable(vm, QemuVirtMachine)

    while vm.qmp_greeting == nil do
        vm.qmp_greeting = vm:receive_from_qmp()
    end
    vm:send_qmp_and_receive_laggy_consider_not_using({
        execute =
        "qmp_capabilities", -- enter command mode or whatever, basically just make the qemu monitor useful instead of just sitting there
    })
    return vm
end

setmetatable(QemuVirtMachine, { __call = function(_, ...) return QemuVirtMachine.new(...) end })

function QemuVirtMachine:kill()
    assert(validate_bash_str(self.info.vm_path))
    local file = ie.io.open(self.info.vm_path .. "_pid", "r") -- a temporary file
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
    local json = virt.json.encode(table)
    return self.monitor_input:write(json)
end

function QemuVirtMachine:receive_from_qmp()
    assert(validate_bash_str(self.name))
    local proc = ie.io.popen(
        "timeout " .. cat_timeout .. " cat " .. get_vm_file_path_from_name(self.name) .. "_monitor.out", "r")
    local ret = proc:read("*a")
    proc:close()

    if #ret == 0 then return nil end
    return virt.json.decode(ret)
end

-- consider not using....
-- but i understand if its the only reliable way
function QemuVirtMachine:send_qmp_and_receive_laggy_consider_not_using(table)
    self:send_qmp_command(table)
    local out
    while out == nil do
        out = self:receive_from_qmp()
    end
    return out
end

-- serial I/O
-- \n is enter btw
function QemuVirtMachine:send_input(input)
    return self.serial_input:write(input)
end

function QemuVirtMachine:get_output()
    assert(validate_bash_str(self.info.vm_path))
    local proc = ie.io.popen("timeout " .. cat_timeout .. " cat " .. self.info.vm_path .. "_serial.out", "r")
    local ret = proc:read("*a")
    proc:close()

    return ret
end

-- util: send keycombo
-- keycombo: a string seperated by "-"
function QemuVirtMachine:send_keycombo(keycombo)
    keycombo = string.split(keycombo, "-")
    local inp = ""
    local i = 1
    while i <= #keycombo do
        local v = keycombo[i]
        if tonumber(v) then
            inp = inp .. string.char(math.max(0, math.min(255, tonumber(v))))
        elseif v == "ctrl" then
            i = i + 1
            local foward = keycombo[i]
            if foward and #foward == 1 then
                inp = inp .. string.char(math.abs(string.byte(string.upper(foward)) - 64))
            else
                break
            end
        elseif v == "esc" then
            inp = inp .. string.char(0x1b)
        elseif v == "del" then
            inp = inp .. string.char(0x7F)
        elseif v == "ret" or v == "enter" then
            inp = inp .. "\n"
        elseif v == "backspace" or v == "bs" then
            inp = inp .. string.char(0x08)
        elseif v == "tab" then
            inp = inp .. string.char(0x09)
        elseif v == "null" then
            inp = inp .. string.char(0)
        else
            inp = inp .. v
        end
        i = i + 1
    end

    return self:send_input(inp)
end

-- QMP command wrappers

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
    return self:send_qmp_and_receive_laggy_consider_not_using({
        execute = "human-monitor-command",
        ["command-line"] = command_line,
        ["cpu-index"] = cpu_index,
    })
end

make_function_for("system-powerdown", "powerdown")
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
if load_example_frontend then
    dofile(MP .. "/example_frontend.lua")
end

-- chatcommands

minetest.register_chatcommand("make_vm_from_base", {
    params = "<name> <base> [resize]",
    privs = { server = true },
    func = function(player_name, param)
        local params = string.split(param, " ")
        local name = params[1]
        local base = params[2]
        local resize = params[3]
        if not name then
            minetest.chat_send_player(player_name, "Missing name argument")
            return
        elseif not base then
            minetest.chat_send_player(player_name, "Missing base argument")
            return
        end
        virt.create_vm_from_base(name, base, resize)
        minetest.chat_send_player(player_name, "Made the vm!")
    end

})

minetest.register_chatcommand("kill_all_vms", {
    privs = { server = true },
    func = function(player_name)
        for k, v in pairs(virt.machines) do
            v:kill()
        end
        minetest.chat_send_player(player_name, "killed all vms")
    end
})
