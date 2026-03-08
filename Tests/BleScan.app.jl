# Bluetooth iBeacon Scanner via D-Bus / GIO
const libgio = "libgio-2.0.so.0"
const libglib = "libglib-2.0.so.0"

g_variant_get_fixed_array(v, n, elem_size) = @ccall libglib.g_variant_get_fixed_array(v::Ptr{Cvoid}, n::Ptr{Csize_t}, elem_size::Csize_t)::Ptr{Cvoid}

function variant_bytes(v::Ptr{Cvoid})
    n = Ref{Csize_t}(0)
    p = g_variant_get_fixed_array(v, n, 1) |> Ptr{UInt8}
    (p == C_NULL || n[] == 0) && return UInt8[]
    return copy(unsafe_wrap(Vector{UInt8}, p, Int(n[]); own=false))
end

hex2(b::UInt8) = uppercase(string(b, base=16, pad=2))

function uuid_from_16(bytes16::Vector{UInt8})
    length(bytes16) == 16 || return nothing
    p1 = join(hex2.(bytes16[1:4]))
    p2 = join(hex2.(bytes16[5:6]))
    p3 = join(hex2.(bytes16[7:8]))
    p4 = join(hex2.(bytes16[9:10]))
    p5 = join(hex2.(bytes16[11:16]))
    return "$p1-$p2-$p3-$p4-$p5"
end

function parse_ibeacon_payload(payload::Vector{UInt8})
    # iBeacon payload (after company id) is:
    # 0x02 0x15 + 16-byte UUID + 2-byte major + 2-byte minor + 1-byte tx power
    length(payload) >= 23 || return nothing
    payload[1] == 0x02 && payload[2] == 0x15 || return nothing

    uuid = uuid_from_16(payload[3:18])
    uuid === nothing && return nothing

    major = (UInt16(payload[19]) << 8) | UInt16(payload[20])
    minor = (UInt16(payload[21]) << 8) | UInt16(payload[22])
    return (uuid=uuid, major=major, minor=minor)
end

g_variant_classify(v) = @ccall libglib.g_variant_classify(v::Ptr{Cvoid})::UInt8
g_variant_get_variant(v) = @ccall libglib.g_variant_get_variant(v::Ptr{Cvoid})::Ptr{Cvoid}
g_variant_n_children(v) = @ccall libglib.g_variant_n_children(v::Ptr{Cvoid})::Csize_t
g_variant_get_child_value(v, index) = @ccall libglib.g_variant_get_child_value(v::Ptr{Cvoid}, index::Csize_t)::Ptr{Cvoid}
g_variant_get_uint16(v) = @ccall libglib.g_variant_get_uint16(v::Ptr{Cvoid})::UInt16

function extract_ibeacon_from_manufacturer_data(mfg_v::Ptr{Cvoid})
    mfg_v == C_NULL && return nothing

    # Handle both direct a{qv} and boxed variant(v)
    cls = g_variant_classify(mfg_v)
    dict_v = mfg_v
    boxed = false
    if cls == UInt8('v')
        dict_v = g_variant_get_variant(mfg_v)
        boxed = true
    end
    dict_v == C_NULL && return nothing

    n = g_variant_n_children(dict_v)
    for i in 0:(n - 1)
        entry_v = g_variant_get_child_value(dict_v, i)
        entry_v == C_NULL && continue

        cid_v = g_variant_get_child_value(entry_v, 0)
        val_v = g_variant_get_child_value(entry_v, 1)

        cid = cid_v == C_NULL ? UInt16(0) : g_variant_get_uint16(cid_v)

        if cid == 0x004c && val_v != C_NULL
            # val_v is variant(ay)
            payload_v = g_variant_get_variant(val_v)
            payload = payload_v == C_NULL ? UInt8[] : variant_bytes(payload_v)
            ibeacon = parse_ibeacon_payload(payload)

            payload_v != C_NULL && g_variant_unref(payload_v)
            cid_v != C_NULL && g_variant_unref(cid_v)
            val_v != C_NULL && g_variant_unref(val_v)
            g_variant_unref(entry_v)
            boxed && g_variant_unref(dict_v)

            return ibeacon
        end

        cid_v != C_NULL && g_variant_unref(cid_v)
        val_v != C_NULL && g_variant_unref(val_v)
        g_variant_unref(entry_v)
    end

    boxed && g_variant_unref(dict_v)
    return nothing
end

function mac_from_dev_path(path::AbstractString)
    m = match(r"/dev_([0-9A-Fa-f_]+)$", path)
    m === nothing && return nothing
    mac = uppercase(replace(m.captures[1], "_" => ":"))
    occursin(r"^([0-9A-F]{2}:){5}[0-9A-F]{2}$", mac) ? mac : nothing
end

g_variant_get_child_value(parameters, index) = @ccall libglib.g_variant_get_child_value(parameters::Ptr{Cvoid}, index::Csize_t)::Ptr{Cvoid}
g_variant_get_string(v) = @ccall libglib.g_variant_get_string(v::Ptr{Cvoid}, C_NULL::Ptr{Csize_t})::Ptr{Cchar}
g_variant_lookup_value(dict, key) = @ccall libglib.g_variant_lookup_value(dict::Ptr{Cvoid}, key::Ptr{Cchar}, C_NULL::Ptr{Cvoid})::Ptr{Cvoid}
g_variant_unref(v) = @ccall libglib.g_variant_unref(v::Ptr{Cvoid})::Cvoid

function on_interface_added(connection, sender_name, object_path, interface_name, signal_name, parameters, user_data)
    parameters == C_NULL && return nothing

    # parameters signature: (oa{sa{sv}})
    added_path_v = g_variant_get_child_value(parameters, 0)
    interfaces_v = g_variant_get_child_value(parameters, 1)

    dev_path = ""
    if added_path_v != C_NULL
        p = g_variant_get_string(added_path_v)
        p != C_NULL && (dev_path = unsafe_string(p))
    end

    mac_addr = nothing
    ibeacon = nothing

    if interfaces_v != C_NULL
        dev1_props_v = g_variant_lookup_value(interfaces_v, "org.bluez.Device1")

        if dev1_props_v != C_NULL
            # Address
            addr_v = g_variant_lookup_value(dev1_props_v, "Address")
            if addr_v != C_NULL
                ap = g_variant_get_string(addr_v)
                ap != C_NULL && (mac_addr = unsafe_string(ap))
                g_variant_unref(addr_v)
            end

            # iBeacon from ManufacturerData
            mfg_v = g_variant_lookup_value(dev1_props_v, "ManufacturerData")
            if mfg_v != C_NULL
                ibeacon = extract_ibeacon_from_manufacturer_data(mfg_v)
                g_variant_unref(mfg_v)
            end

            g_variant_unref(dev1_props_v)
        end
    end

    if mac_addr === nothing || isempty(mac_addr)
        mac_addr = mac_from_dev_path(dev_path)
    end

    println("Device discovered at: ", dev_path)
    println("BLE device address: ", mac_addr === nothing ? "(unknown)" : mac_addr)

    if ibeacon !== nothing
        println("iBeacon UUID: ", ibeacon.uuid)
        println("iBeacon Major: ", ibeacon.major)
        println("iBeacon Minor: ", ibeacon.minor)
    end

    if interfaces_v != C_NULL
        g_variant_unref(interfaces_v)
    end
    if added_path_v != C_NULL
        g_variant_unref(added_path_v)
    end

    return nothing
end

g_bus_get_sync(bus_type, cancellable, error) = @ccall libgio.g_bus_get_sync(bus_type::Cint, cancellable::Ptr{Cvoid}, error::Ptr{Ptr{Cvoid}})::Ptr{Cvoid}
g_dbus_connection_signal_subscribe(connection, sender, interface_name, signal_name, callback) = @ccall libgio.g_dbus_connection_signal_subscribe( connection::Ptr{Cvoid}, sender::Ptr{Cchar}, interface_name::Ptr{Cchar}, signal_name::Ptr{Cchar}, C_NULL::Ptr{Cchar}, C_NULL::Ptr{Cchar}, 0::Cint, callback::Ptr{Cvoid}, C_NULL::Ptr{Cvoid}, C_NULL::Ptr{Cvoid} )::UInt32
g_dbus_connection_call_sync(connection, bus_name, object_path, interface_name, method_name, parameters, reply_type, flags, timeout, cancellable, error) = @ccall libgio.g_dbus_connection_call_sync( connection::Ptr{Cvoid}, bus_name::Ptr{Cchar}, object_path::Ptr{Cchar}, interface_name::Ptr{Cchar}, method_name::Ptr{Cchar}, parameters::Ptr{Cvoid}, reply_type::Ptr{Cvoid}, flags::Cint, timeout::Cint, cancellable::Ptr{Cvoid}, error::Ptr{Ptr{Cvoid}} )::Ptr{Cvoid}
g_dbus_connection_call_sync(connection, bus_name, object_path, interface_name, method_name, error) = g_dbus_connection_call_sync( connection, bus_name, object_path, interface_name, method_name, C_NULL, C_NULL, 0, -1, C_NULL, error )

function start_bluez_scanner(adapter_path="/org/bluez/hci0")
    err = Ref{Ptr{Cvoid}}(C_NULL)
    bus = g_bus_get_sync(1, C_NULL, err)
    
    if bus == C_NULL
        error("Failed to connect to System Bus")
    end

    callback_ptr = @cfunction(on_interface_added, Cvoid, (Ptr{Cvoid}, Ptr{Cchar}, Ptr{Cchar}, Ptr{Cchar}, Ptr{Cchar}, Ptr{Cvoid}, Ptr{Cvoid}))
    g_dbus_connection_signal_subscribe(bus, "org.bluez", "org.freedesktop.DBus.ObjectManager", "InterfacesAdded", callback_ptr)
    g_dbus_connection_call_sync(bus, "org.bluez", adapter_path, "org.bluez.Adapter1", "StartDiscovery", err)

    println("BlueZ discovery started on $adapter_path")
    loop = @ccall libglib.g_main_loop_new(C_NULL::Ptr{Cvoid}, 0::Cint)::Ptr{Cvoid}
    @async @ccall libglib.g_main_loop_run(loop::Ptr{Cvoid})::Cvoid
    
    return loop
end

# Run the scanner
scanner_loop = start_bluez_scanner()

wait() 