using Gtk4

win = GtkWindow("UITest", 800, 600)
grid = GtkGrid()
push!(win,grid)

function big_label(text)
    lbl = GtkLabel(text)
    Gtk4.markup(lbl, "<span size='61440'>$(text)</span>")
    return lbl
end 

function expand_button(text)
    lbl = big_label(text)
    btn = GtkButton(lbl)
    btn.hexpand = true
    btn.vexpand = true
    return btn
end

b1 = expand_button("One")
b2 = expand_button("Two")
b3 = expand_button("Three")
b4 = expand_button("Four")

lp = GtkGestureLongPress()
push!(b4, lp)
signal_connect(lp, "pressed") do gesture, x, y
    @info "Long press detected at coordinates: $x, $y"
    Gtk4.G_.set_state(gesture, Gtk4.EventSequenceState_CLAIMED)
end

grid[1,1] = b1
grid[2,1] = b2
grid[1,2] = b3
grid[2,2] = b4  

@async Gtk4.GLib.glib_main()
Gtk4.GLib.waitforsignal(win,:close_request)