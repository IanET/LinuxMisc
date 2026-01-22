using Gtk4

win = GtkWindow("UITest", 800, 600)
grid = GtkGrid()
push!(win,grid)

function big_button(text)
    lbl = GtkLabel(text)
    btn = GtkButton(lbl)
    Gtk4.markup(lbl, "<span size='61440'>$(text)</span>")
    btn.hexpand = true
    btn.vexpand = true
    return btn
end

b1 = big_button("One")
b2 = big_button("Two")
b3 = big_button("Three")
b4 = big_button("Four")

grid[1,1] = b1
grid[2,1] = b2
grid[1,2] = b3
grid[2,2] = b4  

@async Gtk4.GLib.glib_main()
Gtk4.GLib.waitforsignal(win,:close_request)