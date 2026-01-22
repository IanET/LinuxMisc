using Gtk4

win = GtkWindow("UITest", 800, 600)
fullscreen(win)
grid = GtkGrid()
grid.column_homogeneous = true
push!(win,grid)

function big_label_expanded(text, sub)
    lbl = GtkLabel(text)
    Gtk4.markup(lbl, "<span size='61440'>$(text)</span>\n<span size='32768'>$(sub)</span>")
    set_gtk_property!(lbl, :justify, Gtk4.Justification_CENTER)
    lbl.hexpand = true
    lbl.vexpand = true
    return lbl
end 

function big_label(text)
    lbl = GtkLabel(text)
    Gtk4.markup(lbl, "<span size='51200'>$(text)</span>")
    return lbl
end 

function big_button(text)
    lbl = big_label(text)
    btn = GtkButton(lbl)
    signal_connect(btn, "clicked") do btn
        @info "Button '$text' clicked"
    end
    btn.hexpand = true
    return btn
end

title = GtkLabel("")
Gtk4.markup(title, "<span size='32768' weight='bold'>UITest Application</span>")

l1 = big_label_expanded("80", "°C")
l2 = big_label_expanded("4.1", "Gal")
l3 = big_label_expanded("45", "ABV")
b1 = big_button("Log")
b2 = big_button("Pause")
b3 = big_button("Delete")

Gtk4.G_.attach(grid, title, 0, 0, 3, 1)
grid[1,2] = l1
grid[2,2] = l2
grid[3,2] = l3
grid[1,3] = b1
grid[2,3] = b2
grid[3,3] = b3

@async Gtk4.GLib.glib_main()
Gtk4.GLib.waitforsignal(win,:close_request)