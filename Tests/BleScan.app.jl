# Bluetooth iBeacon Scanner via D-Bus / GIO
const libgio = "libgio-2.0.so.0"
const libglib = "libglib-2.0.so.0"

function mac_from_dev_path(path::AbstractString)
    m = match(r"/dev_([0-9A-Fa-f_]+)$", path)
    m === nothing && return nothing
    mac = uppercase(replace(m.captures[1], "_" => ":"))
    occursin(r"^([0-9A-F]{2}:){5}[0-9A-F]{2}$", mac) ? mac : nothing
end

# GDBus Signal Callback
function on_interface_added(connection, sender_name, object_path, interface_name, signal_name, parameters, user_data)
    parameters == C_NULL && return nothing

    # parameters signature: (oa{sa{sv}})
    added_path_v = @ccall libglib.g_variant_get_child_value(
        parameters::Ptr{Cvoid}, 0::Csize_t
    )::Ptr{Cvoid}
    interfaces_v = @ccall libglib.g_variant_get_child_value(
        parameters::Ptr{Cvoid}, 1::Csize_t
    )::Ptr{Cvoid}

    dev_path = ""
    if added_path_v != C_NULL
        p = @ccall libglib.g_variant_get_string(
            added_path_v::Ptr{Cvoid}, C_NULL::Ptr{Csize_t}
        )::Ptr{Cchar}
        p != C_NULL && (dev_path = unsafe_string(p))
    end

    mac_addr = nothing

    # Try preferred source: org.bluez.Device1.Address
    if interfaces_v != C_NULL
        dev1_props_v = @ccall libglib.g_variant_lookup_value(
            interfaces_v::Ptr{Cvoid},
            "org.bluez.Device1"::Ptr{Cchar},
            C_NULL::Ptr{Cvoid}
        )::Ptr{Cvoid}

        if dev1_props_v != C_NULL
            addr_v = @ccall libglib.g_variant_lookup_value(
                dev1_props_v::Ptr{Cvoid},
                "Address"::Ptr{Cchar},
                C_NULL::Ptr{Cvoid}
            )::Ptr{Cvoid}

            if addr_v != C_NULL
                ap = @ccall libglib.g_variant_get_string(
                    addr_v::Ptr{Cvoid}, C_NULL::Ptr{Csize_t}
                )::Ptr{Cchar}
                ap != C_NULL && (mac_addr = unsafe_string(ap))
                @ccall libglib.g_variant_unref(addr_v::Ptr{Cvoid})::Cvoid
            end
            @ccall libglib.g_variant_unref(dev1_props_v::Ptr{Cvoid})::Cvoid
        end
    end

    # Fallback: derive MAC from /dev_XX_XX_...
    if mac_addr === nothing || isempty(mac_addr)
        mac_addr = mac_from_dev_path(dev_path)
    end

    println("Device discovered at: ", dev_path)
    println("BLE device address: ", mac_addr === nothing ? "(unknown)" : mac_addr)

    if interfaces_v != C_NULL
        @ccall libglib.g_variant_unref(interfaces_v::Ptr{Cvoid})::Cvoid
    end
    if added_path_v != C_NULL
        @ccall libglib.g_variant_unref(added_path_v::Ptr{Cvoid})::Cvoid
    end

    # TODO - Find iBeacons, display the GUID, Major, Minor, and Tx Power from the Advertisement Data
    
    return nothing
end

function start_bluez_scanner(adapter_path="/org/bluez/hci0")
    # 1. Get the System Bus
    err = Ref{Ptr{Cvoid}}(C_NULL)
    bus = @ccall libgio.g_bus_get_sync(1::Cint, C_NULL::Ptr{Cvoid}, err::Ptr{Ptr{Cvoid}})::Ptr{Cvoid}
    
    if bus == C_NULL
        error("Failed to connect to System Bus")
    end

    # 2. Create the Callback closure
    # We use @cfunction to pass our Julia function to the C library
    callback_ptr = @cfunction(on_interface_added, Cvoid, (Ptr{Cvoid}, Ptr{Cchar}, Ptr{Cchar}, Ptr{Cchar}, Ptr{Cchar}, Ptr{Cvoid}, Ptr{Cvoid}))

    # 3. Subscribe to "InterfacesAdded"
    @ccall libgio.g_dbus_connection_signal_subscribe(
        bus::Ptr{Cvoid},
        "org.bluez"::Ptr{Cchar},
        "org.freedesktop.DBus.ObjectManager"::Ptr{Cchar},
        "InterfacesAdded"::Ptr{Cchar},
        C_NULL::Ptr{Cchar}, # Object path (null for all)
        C_NULL::Ptr{Cchar}, # Arg0 (null)
        0::Cint,            # Flags
        callback_ptr::Ptr{Cvoid},
        C_NULL::Ptr{Cvoid}, # user_data
        C_NULL::Ptr{Cvoid}  # user_data_free_func
    )::UInt32

    # 4. Start Discovery on the Adapter
    @ccall libgio.g_dbus_connection_call_sync(
        bus::Ptr{Cvoid},
        "org.bluez"::Ptr{Cchar},
        adapter_path::Ptr{Cchar},
        "org.bluez.Adapter1"::Ptr{Cchar},
        "StartDiscovery"::Ptr{Cchar},
        C_NULL::Ptr{Cvoid}, # Parameters
        C_NULL::Ptr{Cvoid}, # Reply type
        0::Cint,            # Flags
        -1::Cint,           # Timeout
        C_NULL::Ptr{Cvoid}, # Cancellable
        err::Ptr{Ptr{Cvoid}}
    )::Ptr{Cvoid}

    println("BlueZ discovery started on $adapter_path")

    # 5. Run the GLib Main Loop in a background Task
    loop = @ccall libglib.g_main_loop_new(C_NULL::Ptr{Cvoid}, 0::Cint)::Ptr{Cvoid}
    @async @ccall libglib.g_main_loop_run(loop::Ptr{Cvoid})::Cvoid
    
    return loop
end

# Run the scanner
scanner_loop = start_bluez_scanner()

wait() 