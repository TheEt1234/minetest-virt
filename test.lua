vm = virt.QemuVirtMachine.new("test", { memory = "3G" })
out = ""
f = function()
    out = out .. vm:get_output()
    minetest.show_formspec("singleplayer", "lol", "formspec_version[7]size[20,20]" ..
        virt.make_terminal(out, {
            x = 0,
            y = 0,
            w = 20,
            h = 20,
            size = 0.3,
            scroll = 0
        }))
    minetest.after(0.5, f)
end

f2 = function(tex, scroll)
    minetest.show_formspec("singleplayer", "lol", "formspec_version[7]size[20,20]" ..
        virt.make_terminal(tex, {
            x = 1,
            y = 1,
            w = 18,
            h = 8,
            size = 0.3,
            scroll = scroll or 0
        }) .. "textarea[0,10;20,10;a;;" .. minetest.formspec_escape(tex):gsub("\x1b", "\\x1b") .. "]")
end
