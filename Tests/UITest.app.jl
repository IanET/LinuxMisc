using Gtk4

const LARGE_FONT = 70*1024
const MEDIUM_FONT = 20*1024
const SMALL_FONT = 15*1024

const css = """
window, .background {
    background-color: #2c3e50;
    color: white;
}
label {
    color: white;
    font-size: 32px;
}
button {
    background-color: #333333; 
    background-image: none;   
    color: white;             
    border-image: none;        
    border: 1px solid #555;   
    box-shadow: none;       
    margin: 0px;               
    padding: 0px 0px;           
}
button:active {
    background-color: #444444;
}
window.dialog {
    background-color: #502C2C;
    color: white; /* Ensures text is readable on dark background */
}
.set-button {
    background-color: Green;
}
.label-border {
    border: 0.25px solid white;
}
"""

provider = Gtk4.GtkCssProvider(css)
win = GtkWindow("UITest", 800, 600)
display = Gtk4.display(win)
push!(display, provider, Gtk4.STYLE_PROVIDER_PRIORITY_APPLICATION)

fullscreen(win)
grid = GtkGrid()
grid.column_homogeneous = true
push!(win,grid)

function big_label_expanded(text, units, sub="")
    lbl = GtkLabel(text)
    add_css_class(lbl, "label-border")
    Gtk4.markup(lbl, "<span size='$LARGE_FONT'>$(text)</span>\n <span size='$MEDIUM_FONT'>$(units)</span>\n\n <span size='$SMALL_FONT'>$(sub)</span>")
    set_gtk_property!(lbl, :justify, Gtk4.Justification_CENTER)
    lbl.hexpand = true
    lbl.vexpand = true
    return lbl
end 

function big_label(text)
    lbl = GtkLabel(text)
    Gtk4.markup(lbl, "<span>$(text)</span>")
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
Gtk4.markup(title, "<span size='24576' weight='bold'>UITest Application</span>")

b1 = big_button("On")
b2 = big_button("Off")
b3 = big_button("Auto")
l1 = big_label_expanded("95.5", "°C", "80 ABV")
l2 = big_label_expanded("4.1", "Gal", "12.1 cm")
l3 = big_label_expanded("45.0", "ABV", "0.995 SG")
b4 = big_button("Log")
b5 = big_button("Pause")
b6 = big_button("Delete")

signal_connect(b6, "clicked") do btn
    ask_dialog("\nAre you sure you want to proceed?\n", win; no_text="No", yes_text="Yes") do x
        @info "User clicked $x"
    end
end

signal_connect(b1, "clicked") do btn
    Gtk4.markup(title, "<span size='24576' weight='bold'>On</span>")
    add_css_class(btn, "set-button")
    remove_css_class(b2, "set-button")
    remove_css_class(b3, "set-button")
end

signal_connect(b2, "clicked") do btn
    Gtk4.markup(title, "<span size='24576' weight='bold'>Off</span>")
    add_css_class(btn, "set-button")
    remove_css_class(b1, "set-button")
    remove_css_class(b3, "set-button")
end

signal_connect(b3, "clicked") do btn
    Gtk4.markup(title, "<span size='24576' weight='bold'>Auto</span>")
    add_css_class(btn, "set-button")
    remove_css_class(b1, "set-button")
    remove_css_class(b2, "set-button")
end

signal_connect(b4, "clicked") do btn
    Gtk4.markup(title, "<span size='24576' weight='bold'>Log</span>")
    add_css_class(btn, "set-button")
    remove_css_class(b5, "set-button")
end

signal_connect(b5, "clicked") do btn
    Gtk4.markup(title, "<span size='24576' weight='bold'>Log</span>")
    add_css_class(btn, "set-button")
    remove_css_class(b4, "set-button")
end

grid[1,1] = b1
grid[2,1] = b2
grid[3,1] = b3
Gtk4.G_.attach(grid, title, 0, 1, 3, 1)
grid[1,3] = l1
grid[2,3] = l2
grid[3,3] = l3
grid[1,4] = b4
grid[2,4] = b5
grid[3,4] = b6

@async Gtk4.GLib.glib_main()
Gtk4.GLib.waitforsignal(win,:close_request)