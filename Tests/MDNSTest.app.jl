import Base.GC.@preserve

# Avahi libraries
const libavahi_common = "libavahi-common.so.3"
const libavahi_client = "libavahi-client.so.3"

# Constants
const AVAHI_IF_UNSPEC::Int32 = -1
const AVAHI_PROTO_UNSPEC::Int32 = -1
const AVAHI_RESOLVER_FOUND::Int32 = 0
const AVAHI_RESOLVER_FAILURE::Int32 = 1
const AVAHI_BROWSER_NEW::Int32 = 0
const AVAHI_BROWSER_REMOVE::Int32 = 1
const AVAHI_BROWSER_CACHE_EXHAUSTED::Int32 = 2
const AVAHI_BROWSER_ALL_FOR_NOW::Int32 = 3
const AVAHI_BROWSER_FAILURE::Int32 = 4
const AVAHI_CLIENT_FAILURE::Int32 = 100
const AVAHI_LOOKUP_RESULT_CACHED::Int32 = 1
const AVAHI_LOOKUP_RESULT_WIDE_AREA::Int32 = 2
const AVAHI_LOOKUP_RESULT_MULTICAST::Int32 = 4
const AVAHI_LOOKUP_RESULT_LOCAL::Int32 = 8
const AVAHI_LOOKUP_RESULT_OUR_OWN::Int32 = 16
const AVAHI_ADDRESS_STR_MAX = 40

# Wrapper functions for Avahi API
avahi_simple_poll_new() = @ccall libavahi_common.avahi_simple_poll_new()::Ptr{Cvoid}
avahi_simple_poll_get(simple_poll) = @ccall libavahi_common.avahi_simple_poll_get(simple_poll::Ptr{Cvoid})::Ptr{Cvoid}
avahi_client_new(poll, flags, callback, userdata, error) = @ccall libavahi_client.avahi_client_new(poll::Ptr{Cvoid}, flags::Int32, callback::Ptr{Cvoid}, userdata::Ptr{Cvoid}, error::Ptr{Int32})::Ptr{Cvoid}
avahi_strerror(error) = @ccall libavahi_common.avahi_strerror(error::Int32)::Cstring
avahi_simple_poll_free(simple_poll) = @ccall libavahi_common.avahi_simple_poll_free(simple_poll::Ptr{Cvoid})::Cvoid
avahi_client_errno(client) = @ccall libavahi_client.avahi_client_errno(client::Ptr{Cvoid})::Int32
avahi_service_browser_new(client, interface, protocol, type, domain, flags, callback, userdata) = @ccall libavahi_client.avahi_service_browser_new(client::Ptr{Cvoid}, interface::Int32, protocol::Int32, type::Cstring, domain::Ptr{Cvoid}, flags::Int32, callback::Ptr{Cvoid}, userdata::Ptr{Cvoid})::Ptr{Cvoid}
avahi_service_browser_free(sb) = @ccall libavahi_client.avahi_service_browser_free(sb::Ptr{Cvoid})::Cvoid
avahi_client_free(client) = @ccall libavahi_client.avahi_client_free(client::Ptr{Cvoid})::Cvoid
avahi_simple_poll_loop(simple_poll) = @ccall libavahi_common.avahi_simple_poll_loop(simple_poll::Ptr{Cvoid})::Cvoid
avahi_simple_poll_quit(simple_poll) = @ccall libavahi_common.avahi_simple_poll_quit(simple_poll::Ptr{Cvoid})::Cvoid
avahi_service_browser_get_client(b) = @ccall libavahi_client.avahi_service_browser_get_client(b::Ptr{Cvoid})::Ptr{Cvoid}
avahi_service_resolver_new(client, interface, protocol, name, type, domain, aprotocol, flags, callback, userdata) = @ccall libavahi_client.avahi_service_resolver_new(client::Ptr{Cvoid}, interface::Int32, protocol::Int32, name::Cstring, type::Cstring, domain::Cstring, aprotocol::Int32, flags::Int32, callback::Ptr{Cvoid}, userdata::Ptr{Cvoid})::Ptr{Cvoid}
avahi_service_resolver_free(r) = @ccall libavahi_client.avahi_service_resolver_free(r::Ptr{Cvoid})::Cvoid
avahi_address_snprint(buf, size, address) = @ccall libavahi_common.avahi_address_snprint(buf::Ptr{UInt8}, size::Csize_t, address::Ptr{Cvoid})::Ptr{UInt8}
avahi_string_list_to_string(txt) = @ccall libavahi_common.avahi_string_list_to_string(txt::Ptr{Cvoid})::Cstring
avahi_string_list_get_service_cookie(txt) = @ccall libavahi_common.avahi_string_list_get_service_cookie(txt::Ptr{Cvoid})::Int32
avahi_free(ptr) = @ccall libavahi_common.avahi_free(ptr::Ptr{Cvoid})::Cvoid

# Global variables for callbacks
c_resolve_callback = C_NULL
c_browse_callback = C_NULL
c_client_callback = C_NULL

function resolve_callback(r::Ptr{Cvoid}, interface::Int32, protocol::Int32, event::Int32, name::Cstring, type::Cstring, domain::Cstring, host_name::Cstring, address::Ptr{Cvoid}, port::UInt16, txt::Ptr{Cvoid}, flags::Int32, userdata::Ptr{Cvoid})
    name = name != C_NULL ? unsafe_string(name) : ""
    type = type != C_NULL ? unsafe_string(type) : ""
    domain = domain != C_NULL ? unsafe_string(domain) : ""
    host_name = host_name != C_NULL ? unsafe_string(host_name) : ""
    if event == AVAHI_RESOLVER_FAILURE
        error_str = avahi_strerror(avahi_client_errno(userdata)) |> unsafe_string
        println(stderr, "(Resolver) Failed to resolve service '", name, "' of type '", type, "' in domain '", domain, "': ", error_str)
    elseif event == AVAHI_RESOLVER_FOUND
        a = Vector{UInt8}(undef, AVAHI_ADDRESS_STR_MAX)
        @preserve a avahi_address_snprint(pointer(a), sizeof(a), address)
        t = avahi_string_list_to_string(txt)
        cookie = avahi_string_list_get_service_cookie(txt)
        println(stderr, "Service '", name, "' of type '", type, "' in domain '", domain, "':")
        @preserve a println(stderr, "\t", host_name, ":", port, " (", unsafe_string(pointer(a)), ")")
        println(stderr, "\tTXT=", unsafe_string(t))
        println(stderr, "\tcookie is ", cookie)
        println(stderr, "\tis_local: ", (flags & AVAHI_LOOKUP_RESULT_LOCAL) != 0)
        println(stderr, "\tour_own: ", (flags & AVAHI_LOOKUP_RESULT_OUR_OWN) != 0)
        println(stderr, "\twide_area: ", (flags & AVAHI_LOOKUP_RESULT_WIDE_AREA) != 0)
        println(stderr, "\tmulticast: ", (flags & AVAHI_LOOKUP_RESULT_MULTICAST) != 0)
        println(stderr, "\tcached: ", (flags & AVAHI_LOOKUP_RESULT_CACHED) != 0)
        avahi_free(Ptr{Cvoid}(t))
    end
    avahi_service_resolver_free(r)
end

function browse_callback(b::Ptr{Cvoid}, interface::Int32, protocol::Int32, event::Int32, name::Cstring, type::Cstring, domain::Cstring, flags::Int32, userdata::Ptr{Cvoid})
    simple_poll = userdata
    c = avahi_service_browser_get_client(b)
    name = name != C_NULL ? unsafe_string(name) : ""
    type = type != C_NULL ? unsafe_string(type) : ""
    domain = domain != C_NULL ? unsafe_string(domain) : ""

    if event == AVAHI_BROWSER_FAILURE
        error_str = avahi_strerror(avahi_client_errno(c))
        println(stderr, "(Browser) Failure ", unsafe_string(error_str))
        avahi_simple_poll_quit(simple_poll)
        return
    elseif event == AVAHI_BROWSER_NEW
        println(stderr, "(Browser) NEW: service '", name, "' of type '", type, "' in domain '", domain, "'")
        if name[1] != '_'  # Skip meta-browse entries
            resolver = avahi_service_resolver_new(c, interface, protocol, name, type, domain, AVAHI_PROTO_UNSPEC, Int32(0), c_resolve_callback, c)
            if resolver == C_NULL
                error_str = avahi_strerror(avahi_client_errno(c))
                println(stderr, "Failed to resolve service '", name, "': ", unsafe_string(error_str))
            end
        end
        # TODO If doing a meta browse, create a new service browser here
    elseif event == AVAHI_BROWSER_REMOVE
        println(stderr, "(Browser) REMOVE: service '", name, "' of type '", type, "' in domain '", domain, "'")
    elseif event == AVAHI_BROWSER_ALL_FOR_NOW || event == AVAHI_BROWSER_CACHE_EXHAUSTED
        msg = event == AVAHI_BROWSER_CACHE_EXHAUSTED ? "CACHE_EXHAUSTED" : "ALL_FOR_NOW"
        println(stderr, "(Browser) ", msg)
    end
end

function client_callback(c::Ptr{Cvoid}, state::Int32, userdata::Ptr{Cvoid})
    @info "Client state changed: $state"
    simple_poll = userdata
    if state == AVAHI_CLIENT_FAILURE
        errno = avahi_client_errno(c)
        error_str = avahi_strerror(errno)
        println(stderr, "Server connection failure: $errno ", unsafe_string(error_str))
        avahi_simple_poll_quit(simple_poll)
    end
end

# dns-sd service "_services._dns-sd._udp.local"

# Main function
function main(args::Vector{String})
    if length(args) < 1
        println("Usage: julia ", PROGRAM_FILE, " <service_type>")
        println("Example: julia ", PROGRAM_FILE, " _http._tcp")
        return 1
    end

    service_type = args[1]

    # Create cfunctions
    global c_resolve_callback = @cfunction(resolve_callback, Cvoid, (Ptr{Cvoid}, Int32, Int32, Int32, Cstring, Cstring, Cstring, Cstring, Ptr{Cvoid}, UInt16, Ptr{Cvoid}, Int32, Ptr{Cvoid}))
    global c_browse_callback = @cfunction(browse_callback, Cvoid, (Ptr{Cvoid}, Int32, Int32, Int32, Cstring, Cstring, Cstring, Int32, Ptr{Cvoid}))
    global c_client_callback = @cfunction(client_callback, Cvoid, (Ptr{Cvoid}, Int32, Ptr{Cvoid}))

    simple_poll = avahi_simple_poll_new()
    if simple_poll == C_NULL
        println(stderr, "Failed to create simple poll object.")
        return 1
    end

    error = Ref{Int32}(0)
    spg = avahi_simple_poll_get(simple_poll)
    client = avahi_client_new(spg, Int32(0), c_client_callback, simple_poll, error)
    if client == C_NULL
        error_str = avahi_strerror(error[])
        println(stderr, "Failed to create client: ", unsafe_string(error_str))
        avahi_simple_poll_free(simple_poll)
        return 1
    end

    sb = avahi_service_browser_new(client, AVAHI_IF_UNSPEC, AVAHI_PROTO_UNSPEC, service_type, C_NULL, Int32(0), c_browse_callback, simple_poll)
    @info "Browsing for services of type '$service_type'"
    if sb == C_NULL
        error_str = avahi_strerror(avahi_client_errno(client))
        println(stderr, "Failed to create service browser: ", unsafe_string(error_str))
        avahi_client_free(client)
        avahi_simple_poll_free(simple_poll)
        return 1
    end

    avahi_simple_poll_loop(simple_poll)

    avahi_service_browser_free(sb)
    avahi_client_free(client)
    avahi_simple_poll_free(simple_poll)

    return 0
end

# Run main if this is the script
if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
