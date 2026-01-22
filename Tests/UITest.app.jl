using Gtk4

css = """
window, .background {
    background-color: #2c3e50;
    color: white;
}
label {
    color: white;
    font-size: 32px;
}
button {
    background-color: #333333; /* Dark Gray */
    background-image: none;    /* REQUIRED: Removes the default gradient */
    color: white;              /* Text color */
    border-image: none;        /* Removes theme-specific border styling */
    border: 1px solid #555;    /* Gives it a visible edge */
    box-shadow: none;          /* Removes default glow/shadow */
}
button:active {
    background-color: #444444;
}
window.dialog {
    background-color: #502C2C;
    color: white; /* Ensures text is readable on dark background */
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

function big_label_expanded(text, sub)
    lbl = GtkLabel(text)
    Gtk4.markup(lbl, "<span size='81920'>$(text)</span>\n<span size='20480'>$(sub)</span>")
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
Gtk4.markup(title, "<span size='32768' weight='bold'>UITest Application</span>")

l1 = big_label_expanded("80", "°C")
l2 = big_label_expanded("4.1", "Gal")
l3 = big_label_expanded("45", "ABV")
b1 = big_button("Log")
b2 = big_button("Pause")
b3 = big_button("Delete")

signal_connect(b3, "clicked") do btn
    ask_dialog("\nAre you sure you want to proceed?\n", win; no_text="No", yes_text="Yes") do x
        @info "User clicked $x"
    end
end

Gtk4.G_.attach(grid, title, 0, 0, 3, 1)
grid[1,2] = l1
grid[2,2] = l2
grid[3,2] = l3
grid[1,3] = b1
grid[2,3] = b2
grid[3,3] = b3

@async Gtk4.GLib.glib_main()
Gtk4.GLib.waitforsignal(win,:close_request)