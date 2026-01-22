using Gtk4

win = GtkWindow("UITest", 800, 600)
grid = GtkGrid()
push!(win,grid)

function big_label_expanded(text)
    lbl = GtkLabel(text)
    Gtk4.markup(lbl, "<span size='61440'>$(text)</span>")
    lbl.hexpand = true
    lbl.vexpand = true
    return lbl
end 

function big_label(text)
    lbl = GtkLabel(text)
    Gtk4.markup(lbl, "<span size='61440'>$(text)</span>")
    return lbl
end 

function big_button(text)
    lbl = big_label(text)
    btn = GtkButton(lbl)
    signal_connect(btn, "clicked") do btn
        @info "Button '$text' clicked"
    end
    return btn
end

l1 = big_label_expanded("One")
l2 = big_label_expanded("Two")
l3 = big_label_expanded("Three")
b1 = big_button("Four")
b2 = big_button("Five")
b3 = big_button("Six")

# gesture = GtkGestureClick()
# push!(b4, gesture)
# signal_connect(gesture, "pressed") do g, n_press, x, y
#     Gtk4.G_.set_state(gesture, Gtk4.EventSequenceState_CLAIMED)
#     @info "Button Pressed"
# end

# signal_connect(gesture, "released") do g, n_press, x, y
#     Gtk4.G_.set_state(gesture, Gtk4.EventSequenceState_CLAIMED)
#     # w = Gtk4.widget(g)
#     @info "Button Released"
# end

grid[1,1] = l1
grid[2,1] = l2
grid[3,1] = l3
grid[1,2] = b1
grid[2,2] = b2
grid[3,2] = b3

@async Gtk4.GLib.glib_main()
Gtk4.GLib.waitforsignal(win,:close_request)