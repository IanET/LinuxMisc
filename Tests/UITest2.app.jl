using Gtk4

app = GtkApplication()

Gtk4.signal_connect(app, :activate) do app
    win = GtkApplicationWindow(app, "my title")
    show(win)
    fullscreen(win)
end

run(app)
