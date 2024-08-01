local UPDATE_TIME = 0.5
local SCROLLBACK_SIZE = 10000

vm = virt.QemuVirtMachine("test", {
    memory = "512M",
    nic = true
})

local function rgb2hex(r, g, b)
    if not g then -- greyscale
        return "#" .. string.format("#%02X", r):rep(3)
    else
        return string.format("#%02X%02X%02X", r, g, b)
    end
end

local player = "singleplayer"
local state = {
    paused = false,
    size = 0.3,
    w = 20,
    scroll = 0,
    active = true,
    colors = {
        [0] = { 0, 0, 0 },        -- black
        [1] = { 170, 0, 0 },      -- red
        [2] = { 0, 170, 0 },      -- green
        [3] = { 170, 85, 0 },     -- yellow
        [4] = { 0, 0, 170 },      -- blue
        [5] = { 170, 0, 170 },    -- magenta
        [6] = { 0, 170, 170 },    -- cyan
        [7] = { 170, 170, 170 },  -- white
        [8] = { 85, 85, 85 },     -- bright black
        [9] = { 255, 85, 85 },    -- bright red
        [10] = { 85, 255, 85 },   -- bright green
        [11] = { 255, 255, 85 },  -- bright yellow
        [12] = { 85, 85, 255 },   -- bright blue
        [13] = { 255, 85, 255 },  -- bright magenta
        [14] = { 85, 255, 255 },  -- bright cyan
        [15] = { 255, 255, 255 }, -- bright white
    }
}

local color_names = {
    [0] = "black",
    "red",
    "green",
    "yellow",
    "blue",
    "magenta",
    "cyan",
    "white",
    "bright black",
    "bright red",
    "bright green",
    "bright yellow",
    "bright blue",
    "bright magenta",
    "bright cyan",
    "bright white"
}

local make_settings = function()
    local fs = {}

    for i = 0, 15 do
        fs[#fs + 1] = string.format("box[0,%s;5,2;%s]", i * 2, rgb2hex(unpack(state.colors[i])) .. "FF")
        fs[#fs + 1] = string.format("label[1,%s;%s]", (i * 2) + 1, color_names[i])

        fs[#fs + 1] = string.format("field[6,%s;10,1;%srgb;r,g,b;%s]", (i * 2) + 0.5, i,
            state.colors[i][1] .. "," .. state.colors[i][2] .. "," .. state.colors[i][3])
        fs[#fs + 1] = string.format("field_close_on_enter[%srgb;false]", i)
    end
    fs[#fs + 1] = "button[20,5;5,2;doit;Commit changes]"
    state.active = false
    minetest.show_formspec(player, "virt", "formspec_version[7]size[30,32]" .. table.concat(fs, ""))
end

local out = "\0"

local make_frontend = function(text)
    local pause_or_unpause = ""
    if not state.paused then
        pause_or_unpause = [[
            image_button[1,0;1,1;virt_ui_pause.png;pause;]
            tooltip[pause;Pause]
        ]]
    else
        pause_or_unpause = [[
            image_button[1,0;1,1;virt_ui_resume.png;resume;]
            tooltip[resume;Resume]
        ]]
    end

    local fs = "formspec_version[7]size[" .. state.w .. ",20]" .. [[
        padding[0.001,0.001]
        image_button[0,0;1,1;virt_ui_stop.png;stop;]
        tooltip[stop;Stop the virtual machine (doesn't work and doesn't need to because of how this test works)] ]] ..
        pause_or_unpause .. [[
    image_button[2,0;1,1;virt_ui_settings.png;settings;]
    tooltip[settings;Settings]

    field[3,0;5,1;input;;]
    field_close_on_enter[input;false]
    button[8,0;3,1;submit_with_newline;Send input
with enter]
    button[11,0;3,1;submit_without_newline;Send input
without enter]
    button[14,0;3,1;submit_as_keycomb;Send input
as key combo]
    button[16.5,0.1;0.4,0.4;keycomb_help;?]

    button[17,0;0.5,0.5;size_plus;+]
    button[17.5,0;0.5,0.5;size_minus;-]
    button[18,0;0.5,0.5;screen_size;\[  \] ]
    tooltip[screen_size;Toggle wide screen]

    tooltip[scroll_reset;Reset scroll]
    ]] .. virt.make_terminal(text, {
            x = 0,
            y = 1,
            w = state.w,
            h = 19,
            scroll = state.scroll,
            size = state.size,
        }, {
            color = state.colors
        })

    return fs
end

local function func()
    out = string.sub(out .. vm:get_output(), -SCROLLBACK_SIZE, -1)
    if state.active then
        minetest.show_formspec(player, "virt", make_frontend(out))
    end
    minetest.after(UPDATE_TIME, func)
end
func()

minetest.register_on_player_receive_fields(function(_, formname, fields)
    if formname ~= "virt" then return end
    if fields.submit_without_newline then
        vm:send_input(fields.input)
    elseif fields.submit_as_keycomb then
        vm:send_keycombo(fields.input)
    elseif fields.submit_with_newline then
        vm:send_input(fields.input .. "\n")
    elseif fields.pause then
        state.paused = true
        vm:pause()
    elseif fields.resume then
        state.paused = false
        vm:resume()
    elseif fields.size_plus then
        state.size = state.size + 0.05
    elseif fields.size_minus then
        if state.size > 0.1 then
            state.size = state.size - 0.05
        end
    elseif fields.screen_size then
        if state.w == 20 then
            state.w = 40
        elseif state.w == 40 then
            state.w = 20
        end
    elseif fields.scroll_up then
        state.scroll = state.scroll + 5
    elseif fields.scroll_down then
        state.scroll = state.scroll - 5
        if state.scroll < 0 then state.scroll = 0 end
    elseif fields.scroll_reset then
        state.scroll = 0
    elseif fields.keycomb_help then
        state.active = false
        minetest.show_formspec(player, "virt", "size[20,20]padding[0,0]label[0,0;" .. minetest.formspec_escape([[
Warning: due to the limits of serial console, don't expect to be able to do ctrl-alt-meta-page_down-5, and don't expect to be able to hold a key
The serial console completely ignores the virtual keyboard so yeah
We have to use fancy control characters

Examples:
Typing in ---> result (as escape sequence)

0x41 --> A
ctrl-C --> \x03
ctrl-@ --> \x0


Actual explanation:
So, keys are seperated by "-" (like key1-key2)
When a key is not "valid", it will just be printed out normally
Example: hello wor-ld --> hello world

If you put in a number (like 1-2) it won't actually put 12 but it will put the ascii code 1 and ascii code 2
so if you put in 65-65 it will put AA

So here are the keys that are "valid", uppercase/lowercase matters:

ctrl-[x] - converts [x] into a control character [x], [x] is any character (in this case, [x] will be converted to uppercase)
see https://ss64.com/ascii.html for what you can do with ctrl, but basically ctrl-c stops the program and that's basically it

esc - the escpae character
del - del....
ret/enter - enter... also is a new line
backspace/bs - you get it
tab - ....
null - equivilent to typing in 0
]]) .. "]")
    elseif fields.settings then
        make_settings()
    elseif fields.doit then
        state.active = false
        for i = 0, 15 do
            local split = string.split(fields[tostring(i) .. "rgb"], ",")
            for k, v in ipairs(split) do
                split[k] = tonumber(v) or 0
            end

            state.colors[i] = split
        end
        make_settings()
    elseif fields.quit then
        state.active = true -- nope!
    end
end)
