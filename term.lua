-- so
-- task: implement almost everything relevant in https://en.wikipedia.org/wiki/ANSI_escape_code
-- the only sane way to do this is how lwcomputers did it (it didn't do ansi, but it had background colors n stuff)

-- anyway this code is absolute dogwater
-- lua doesn't provide a switch statement so enjoy if elseif spam

local TAB_SIZE = 8 -- AS DEFINED BY THE SPEC!!!!!! (the spec being wikipedia)


local function rgb2hex(r, g, b)
    if not g then -- greyscale
        return "#" .. string.format("#%02X", r):rep(3)
    else
        return string.format("#%02X%02X%02X", r, g, b)
    end
end

-- 8 bit color as defined by the spec
local eightbit_color_pallete = {}

for r = 0, 5 do
    for g = 0, 5 do
        for b = 0, 5 do
            eightbit_color_pallete[16 + 36 * r + 6 * g + b] = rgb2hex(r, g, b)
        end
    end
end

local function cap_at_one(x)
    if x < 1 then
        return 1
    else
        return x
    end
end

local function in_range(n, p1, p2)
    if p2 < p1 then
        local temp = p1
        p1 = p2
        p2 = temp
    end
    return n >= p1 and n <= p2
end

local byte, char, sub = string.byte, string.char, string.sub

local function font_char(char, state)
    if state.hide then return "" end -- no formspec needed
    local byte = byte(char)

    if (byte <= 32) or (byte > 255) then
        byte = 32 -- space
    end
    local base = ""
    if state.bold and state.italic then
        base = "BI.png"
    elseif state.bold then
        base = "B.png"
    elseif state.italic then
        base = "I.png"
    else -- regular
        base = "R.png"
    end


    -- 225 font chars
    base = base .. "^[verticalframe:225:" .. (byte - 32)
    if state.foreground then base = "(" .. base .. "^[multiply:" .. state.foreground .. ")" end
    if state.background then base = "[fill:16x30:" .. state.background .. "^" .. base end
    return base
end

local function parse_c0(character_byte, output_text, cursor)
    -- https://en.wikipedia.org/wiki/ANSI_escape_code theres a section on c0's, but in short its those weeird ascii characters that you dont know what their pourpourse is until you are 10km deep in a rabbithole
    if character_byte == 0x07 then
        -- its the bell, and no we wont make a sound i dont know how this works exactly
    elseif character_byte == 0x08 then -- the backspace
        output_text[cursor.y][cursor.x] = ""
        cursor.x = cap_at_one(cursor.x - 1)
    elseif character_byte == 0x09 then -- tab
        cursor.x = cursor.x + (cursor.x % TAB_SIZE)
    elseif character_byte == 0x0A then -- line feed, aka the \n YES the mythical \n is being processed here
        cursor.y = cursor.y + 1
        cursor.x = 1                   -- is this what the unix world has done to our escape codes
    elseif character_byte == 0x0C then
        -- "Move a printer to top of next page"
        -- WAIT I THOUGHT THIS WAS FOR ANCIENT TERMINALS, NOT PRINTERS
        -- WHAT THE F###
    elseif character_byte == 0x0D then
        -- its the carriage return, your favoourite microsoft windows ascii character
        cursor.x = 1
    else
        return true
    end
end


-- THE STATE
local saved_cursor = { x = 1, y = 1 }
local cursor_hidden = false

-- "What happens if a screen gets filled with bold italic magenta background pink foreground overlined characters?"
-- lets say thats 100 characters
-- and a max resolution of a terminal is 200x50
-- thats 1 megabyte
-- per update
-- per terminal
-- thats a lot


local graphics_state = {
    bold = false,
    italic = false,
    background = false,
    foreground = false,
    hide = false
}

-- oh the yucky
local function parse_csi(ptr, text, out_text, cursor, real_size, settings)
    local MAX_CSI_LENGTH_OR_YOU_ARE_INSANE = 30

    local parameter_bytes = ""    -- 0x30-0x3F, ASCII 0-9:;<=>? and also 0x70-0x7E ASCII p-z{|}~, those ones are private
    local intermediate_bytes = "" -- 0x20-0x2F ASCII space and !"#$%&'()*+,-./
    local final_byte = ""         -- 0x40-0x7E ASCII @A-Z[\]^_`a-z{|}~

    local counter = 0
    local invalid = true
    while counter < MAX_CSI_LENGTH_OR_YOU_ARE_INSANE do
        counter = counter + 1
        ptr = ptr + 1
        if ptr > #text then
            break
        end

        local character = sub(text, ptr, ptr)
        local character_byte = byte(character)
        if in_range(character_byte, 0x30, 0x3F) or in_range(character_byte, 0x70, 0x7E) then
            parameter_bytes = parameter_bytes .. character
        elseif in_range(character_byte, 0x20, 0x2F) then
            intermediate_bytes = intermediate_bytes .. character
        elseif in_range(character_byte, 0x40, 0x7E) then
            final_byte = character
            invalid = false
            break
        else
            break
        end
    end
    if invalid then return ptr end

    -- horrible helpers
    -- lua metatables can be a footgun, especially __index sometimes
    local args = parameter_bytes:split(";")
    local args_default_0 = setmetatable({}, {
        __index = function(t, k)
            return tonumber(args[k]) or 0
        end
    })
    local args_default_1 = setmetatable({}, {
        __index = function(t, k)
            return tonumber(args[k]) or 1
        end
    })

    -- ok now we have to actually interpret it
    -- it will be fun............ luckily csi starts simple
    -- just to be clear: the final_byte is the command
    -- theese are commands

    if final_byte == "A" then     -- cursor up
        cursor.y = cap_at_one(cursor.y - args_default_1[1])
    elseif final_byte == "B" then -- cursor down
        cursor.y = cap_at_one(cursor.y + args_default_1[1])
    elseif final_byte == "C" then -- cursor foward
        cursor.x = math.min(cursor.x + args_default_1[1], real_size.x)
    elseif final_byte == "D" then -- cursor back
        cursor.x = cap_at_one(cursor.x - args_default_1[1])
    elseif final_byte == "E" then -- moves cursor to beginning of line <n> lines down
        cursor.x = 1
        cursor.y = cap_at_one(cursor.y + args_default_1[1])
    elseif final_byte == "F" then -- moves cursor to beginning of line <n> lines up
        cursor.x = 1
        cursor.y = cap_at_one(cursor.y - args_default_1[1])
    elseif final_byte == "G" then                      -- cursor horizontal absolute
        cursor.y = cap_at_one(args_default_1[1])
    elseif final_byte == "H" or final_byte == "f" then -- cursor position
        cursor.y = cap_at_one(args_default_1[1])
        cursor.x = math.min(cap_at_one(args_default_1[2]), real_size.x)
    elseif final_byte == "J" then -- erase in display
        local n = args_default_0[1]
        if n == 0 then            -- clear from cursor to end
            for k, v in pairs(out_text) do
                if k > cursor.y then
                    out_text[k] = nil
                end
            end
            if out_text[cursor.y] then
                for k, v in pairs(out_text[cursor.y]) do
                    if k >= cursor.x then
                        out_text[cursor.y][k] = nil
                    end
                end
            end
        elseif n == 1 then -- from end to cursor
            for k, v in pairs(out_text) do
                if k < cursor.y then
                    out_text[k] = {}
                end
            end
            if out_text[cursor.y] then
                for k, v in pairs(out_text[cursor.y]) do
                    if k <= cursor.x then
                        out_text[cursor.y][k] = nil
                    end
                end
            end
        elseif n == 2 or n == 3 then -- erase everythin
            for k, v in pairs(out_text) do
                out_text[k] = nil
            end
        end
    elseif final_byte == "K" then -- erase in line
        local n = args_default_0[1]
        if n == 0 then            -- from cursor to end of line
            if out_text[cursor.y] then
                for k, v in pairs(out_text[cursor.y]) do
                    if k <= n then
                        out_text[cursor.y][k] = nil
                    end
                end
            end
        elseif n == 1 then -- from beginning of the line
            if out_text[cursor.y] then
                for k, v in pairs(out_text[cursor.y]) do
                    if k >= n then
                        out_text[cursor.y][k] = nil
                    end
                end
            end
        elseif n == 2 then -- entire line
            if out_text[cursor.y] then
                out_text[cursor.y] = {}
            end
        end
    elseif final_byte == "S" then -- scroll up
        -- "add \n's to the bottom"
        for i = 1, math.min(cap_at_one(args_default_1[1]), 100) do
            table.insert(out_text, {})
        end
    elseif final_byte == "T" then -- scroll down
        -- "add \n's to the top"
        for i = 1, math.min(cap_at_one(args_default_1[1]), 100) do
            table.insert(out_text, 1, {})
        end
    elseif final_byte == "m" then -- oh the no its graphics...
        local n_iter = #args
        if n_iter == 0 then n_iter = 1 end
        for i = 1, n_iter do
            local n = args_default_0[i]
            if n == 0 then -- reset or normal
                for k in pairs(graphics_state) do
                    graphics_state[k] = false
                end
            elseif n == 1 then -- bold
                graphics_state.bold = true
            elseif n == 3 then -- italic
                graphics_state.italic = true
            elseif n == 7 then
                -- invert
                local temp = graphics_state.background or "#000000"
                graphics_state.background = graphics_state.foreground or "#ffffff"
                graphics_state.foreground = temp
            elseif n == 8 then  -- hide
                graphics_state.hide = true
            elseif n == 10 then -- reset font
                graphics_state.bold = false
                graphics_state.italic = false
            elseif n == 22 then
                graphics_state.bold = false
            elseif n == 23 then
                graphics_state.italic = false
            elseif n == 28 then
                graphics_state.hide = false
            elseif in_range(n, 30, 37) then
                -- set foreground color
                graphics_state.foreground = settings.color[n - 30] -- yes colors are 0 indexed
            elseif in_range(n, 90, 97) then
                graphics_state.foreground = settings.color[(n - 90) + 7]
            elseif n == 38 then   -- 5;n   2;r;g;b
                local mode = args_default_0[2]
                if mode == 5 then -- 8bit color
                    local color = args_default_0[3]
                    if math.abs(color) < 15 then
                        graphics_state.foreground = settings.color[color]
                    elseif in_range(color, 16, 231) then
                        -- 6 × 6 × 6 cube (216 colors): 16 + 36 × r + 6 × g + b (0 ≤ r, g, b ≤ 5)
                        graphics_state.foreground = eightbit_color_pallete[color]
                    elseif in_range(color, 232, 255) then -- greyscale from dark to light in 24 steps
                        graphics_state.foreground = rgb2hex((color - 232) * (255 / 23))
                    end
                elseif mode == 2 then -- true color
                    graphics_state.foreground = rgb2hex(args_default_0[3], args_default_0[4], args_default_0[5])
                end
                break
            elseif n == 39 then             -- default foreground color
                graphics_state.foreground = "#ffffff"
            elseif in_range(n, 40, 47) then -- set bacground color
                -- only 8 colors
                graphics_state.background = settings.color[n - 40]
            elseif in_range(n, 100, 107) then
                graphics_state.background = settings.color[(n - 100) + 7]
            elseif n == 48 then   -- you know what this is
                local mode = args_default_0[2]
                if mode == 5 then -- 8bit color
                    local color = args_default_0[3]
                    if math.abs(color) < 15 then
                        graphics_state.background = settings.color[color]
                    elseif in_range(color, 16, 231) then
                        -- 6 × 6 × 6 cube (216 colors): 16 + 36 × r + 6 × g + b (0 ≤ r, g, b ≤ 5)
                        graphics_state.background = eightbit_color_pallete[color]
                    elseif in_range(color, 232, 255) then -- greyscale from dark to light in 24 steps
                        graphics_state.background = rgb2hex((color - 232) * (255 / 23))
                    end
                elseif mode == 2 then -- true color
                    graphics_state.background = rgb2hex(args_default_0[3], args_default_0[4], args_default_0[5])
                end
                break
            elseif n == 49 then -- default background
                graphics_state.background = "#000000"
            end
        end
    elseif final_byte == "s" then -- save cursor
        saved_cursor = table.copy(cursor)
    elseif final_byte == "u" then -- restore cursor
        cursor.x = saved_cursor.x
        cursor.y = saved_cursor.y
    elseif final_byte == "h" and parameter_bytes == "?25" then
        cursor_hidden = false
    elseif final_byte == "l" and parameter_bytes == "?25" then
        cursor_hidden = true
    end

    return ptr
end

-- makes a terminal formspec, inside a container
-- this at least has O(n) complexity *i think*
-- but yeah its horrible
virt.make_terminal = function(text, position, settings)
    settings = settings or {}
    settings.color = settings.color or {
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

    settings.color = table.copy(settings.color)

    if settings.color and type(settings.color[0]) == "table" then
        for i = 0, 15 do
            settings.color[i] = rgb2hex(settings.color[i][1], settings.color[i][2], settings.color[i][3])
        end
    end

    cursor_hidden = false
    saved_cursor = { x = 1, y = 1 }

    position = {
        x = position.x,
        y = position.y,
        w = position.w,
        h = position.h,
        size = position.size,
        size_y = position.size * 2,
        scroll = position.scroll,
    }

    position.w = position.w - 0.5 -- scrollbar space

    graphics_state = {
        bold = false,
        italic = false,
        background = false,
        foreground = false,
        hide = false
    }

    -- this is supposed to be the size in characters
    local real_size = {
        x = math.floor(position.w / position.size),
        y = math.floor(position.h / position.size_y)
    }

    local cursor = { x = 1, y = 1 }
    local out_text = {}

    local ptr = 1
    repeat
        local character = sub(text, ptr, ptr)
        local character_byte = byte(character)
        parse_c0(character_byte, out_text, cursor)
        if character_byte == 0x1b then -- escape sequence, oh the no! oh the no, terrors await
            -- we need to look ahead 1 character
            ptr = ptr + 1
            if ptr > #text then
                break
            end
            character = sub(text, ptr, ptr)
            character_byte = byte(character)
            if character == "[" then
                ptr = parse_csi(ptr, text, out_text, cursor, real_size, settings) or ptr
            else -- oh crap IT'S THE CSI ESCAPE CODES OH NO
                parse_c0(character_byte, out_text, cursor)
            end
        elseif character_byte >= 32 then -- control characters get discarded
            cursor.x = cursor.x + 1
            --[[
            if cursor.x > real_size.x then
                cursor.x = 1
                cursor.y = cursor.y + 1
            end
            --]]
            out_text[cursor.y] = out_text[cursor.y] or {}
            table.insert(out_text[cursor.y], cursor.x, font_char(character, graphics_state))
            -- this is what some people call a war crime, i call it uhh
        end
        ptr = ptr + 1
    until ptr > #text
    cursor.x = cursor.x + 1
    -- ok now with the output text, we need to build a formspec
    local formspec = {
        "container[" .. position.x, "," .. position.y .. "]",
        string.format("box[0,0;%s,%s;#000000FF]", position.w, position.h),
    }


    local max_y = 0
    for k in pairs(out_text) do
        if k > max_y then max_y = k end
    end

    -- all of this is dependant on the fact that the font is really close to 1:2

    local down_y = cap_at_one(max_y - position.scroll)
    local up_y = cap_at_one(down_y - real_size.y + 1)

    if math.abs(up_y - down_y) < position.h then
        down_y = position.h
        up_y = 1
    end

    local fs_escape = minetest.formspec_escape
    local function make_fs_from_tex(tex, x, y, size)
        return string.format("image[%s,%s;%s,%s;%s]", x, y, size + 0.02, size * 2, fs_escape(tex))
    end


    local Y = 0
    for y = up_y, down_y do
        local yv = out_text[y]                -- the array of textures
        if yv ~= nil and next(yv) ~= nil then -- if yv is empty or nil we skip do anything
            for x = 1, real_size.x do
                local xv = yv[x]              -- the texture
                if xv and #xv ~= 0 then
                    formspec[#formspec + 1] = make_fs_from_tex(xv, (x * position.size) - position.size, Y, position.size)
                end
            end
        end
        Y = Y + position.size_y
    end
    formspec[#formspec + 1] = "container_end[]"
    formspec[#formspec + 1] = string.format([[
        box[%s,%s;0.5,%s;#000000]
]], (position.x + position.w), position.y, position.h)
    -- heh unicode :>
    formspec[#formspec + 1] = string.format([[
        button[%s,%s;0.5,0.5;scroll_up;▲]
        button[%s,%s;0.5,0.5;scroll_down;▼]
        button[%s,%s;0.5,0.5;scroll_reset;_]
    ]], (position.x + position.w), position.y,
        (position.x + position.w), (position.y + position.h - 0.5),
        (position.x + position.w), (position.y + position.h - 1)
    )
    return table.concat(formspec, "")
end
