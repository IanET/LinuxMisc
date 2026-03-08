using Sockets

# Constants for the Management API
const AF_BLUETOOTH = 31
const BTPROTO_HCI = 1
const HCI_CHANNEL_CONTROL = 3
const HCI_DEV_NONE = 0xffff

const MGMT_OP_START_DISCOVERY = 0x0023
const MGMT_EV_DEVICE_FOUND = 0x0012

# Structs to match C memory layout
struct MgmtHdr
    opcode::UInt16
    index::UInt16
    len::UInt16
end

function scan_ibeacons()
    # 1. Open the Management Socket
    # socket(AF_BLUETOOTH, SOCK_RAW, BTPROTO_HCI)
    sock_fd = @ccall socket(AF_BLUETOOTH::Cint, 3::Cint, BTPROTO_HCI::Cint)::Cint
    if sock_fd < 0
        error("Could not open Bluetooth socket. Are you root?")
    end

    # 2. Bind to the Management Channel
    # sockaddr_hci layout: family(u16), dev(u16), channel(u16)
    addr = UInt16[AF_BLUETOOTH, HCI_DEV_NONE, HCI_CHANNEL_CONTROL]
    if @ccall(bind(sock_fd::Cint, addr::Ptr{UInt16}, 6::Csize_t)::Cint) < 0
        @ccall close(sock_fd::Cint)::Cint
        error("Bind failed. I/O error or busy.")
    end

    # 3. Start Discovery (Send Command)
    # Header (6 bytes) + Type (1 byte: 7 = LE + BR/EDR)
    cmd = [0x23, 0x00, 0x00, 0x00, 0x01, 0x00, 0x07] # Little endian opcode 0x0023, index 0, len 1
    @ccall write(sock_fd::Cint, cmd::Ptr{UInt8}, 7::Csize_t)::Cssize_t

    println("Scanning for iBeacons using Julia mgmt API...")

    buffer = Vector{UInt8}(undef, 1024)
    
    try
        while true
            len = @ccall read(sock_fd::Cint, buffer::Ptr{UInt8}, 1024::Csize_t)::Cssize_t
            if len < 6; continue; end

            # Parse Header
            opcode = UInt16(buffer[2]) << 8 | buffer[1]
            payload_len = UInt16(buffer[6]) << 8 | buffer[5]

            if opcode == MGMT_EV_DEVICE_FOUND
                # iBeacon prefix check: Apple (4C 00), Type (02), Length (15)
                # Data starts after header (6) and fixed event fields (~14 bytes)
                for i in 20:(len - 4)
                    if buffer[i] == 0x4c && buffer[i+1] == 0x00 && 
                       buffer[i+2] == 0x02 && buffer[i+3] == 0x15
                        
                        # Major/Minor are Big Endian in the packet
                        major = Int(buffer[i+20]) << 8 | buffer[i+21]
                        minor = Int(buffer[i+22]) << 8 | buffer[i+23]
                        
                        # Extract MAC (6 bytes, reverse order)
                        mac = join(string.(reverse(buffer[7:12]), base=16, pad=2), ":")
                        
                        println("[FOUND] $mac | Major: $major | Minor: $minor")
                    end
                end
            end
        end
    finally
        @ccall close(sock_fd::Cint)::Cint
    end
end

scan_ibeacons()