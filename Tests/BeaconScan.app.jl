using Sockets

@info "Scanning for iBeacons using Julia mgmt API..." 

# Constants for the Management API
const AF_BLUETOOTH = 31
const BTPROTO_HCI = 1
const HCI_CHANNEL_CONTROL = 3
const HCI_DEV_NONE = 0xffff

const MGMT_OP_START_DISCOVERY = 0x0023
const MGMT_EV_DEVICE_FOUND = 0x0012
const MGMT_EV_DISCOVERING = 0x0013

function scan_ibeacons()
    # 1. Open the Management Socket
    sock_fd = @ccall socket(AF_BLUETOOTH::Cint, 3::Cint, BTPROTO_HCI::Cint)::Cint
    @assert sock_fd >= 0 "Failed to create Bluetooth socket. Are you root?"

    # 2. Bind to the Management Channel
    addr = UInt16[AF_BLUETOOTH, HCI_DEV_NONE, HCI_CHANNEL_CONTROL]
    if @ccall(bind(sock_fd::Cint, addr::Ptr{UInt16}, 6::Csize_t)::Cint) < 0
        @ccall close(sock_fd::Cint)::Cint
        error("Bind failed. I/O error or busy.")
    end

    io = fdio(sock_fd)

    # 3. Start Discovery (Send Command)
    cmd = [0x23, 0x00, 0x00, 0x00, 0x01, 0x00, 0x07] # Little endian opcode 0x0023, index 0, len 1
    write(io, cmd)

    try
        while true
            buffer = read(io)
            len = length(buffer)
            if len < 6; continue; end

            # Parse Header
            opcode = UInt16(buffer[2]) << 8 | buffer[1]
            index = UInt16(buffer[4]) << 8 | buffer[3]
            payload_len = UInt16(buffer[6]) << 8 | buffer[5]

            # @info "Event Opcode: $opcode | Index: $index | Payload Length: $payload_len bytes"

            if opcode == MGMT_EV_DEVICE_FOUND
                # iBeacon prefix check: Apple (4C 00), Type (02), Length (15)
                # Data starts after header (6) and fixed event fields (~14 bytes)
                for i in 20:(len - 4)
                    if buffer[i] == 0x4c && buffer[i+1] == 0x00 && buffer[i+2] == 0x02 && buffer[i+3] == 0x15
                        # Major/Minor are Big Endian in the packet
                        major = Int(buffer[i+20]) << 8 | buffer[i+21]
                        minor = Int(buffer[i+22]) << 8 | buffer[i+23]
                        # Extract MAC (6 bytes, reverse order)
                        mac = join(string.(reverse(buffer[7:12]), base=16, pad=2), ":")
                        println("[FOUND] $mac | Major: $major | Minor: $minor")
                    end
                end
            elseif opcode == MGMT_EV_DISCOVERING
                if buffer[7] == 0x07 && buffer[8] == 0x01
                    @info "Starting"
                elseif buffer[7] == 0x07 && buffer[8] == 0x00
                    @info "Stopping"
                    close(io)
                    return
                end
            end
            sleep(0.1) # Avoid busy loop
        end
    finally
        @ccall close(sock_fd::Cint)::Cint
    end
end

@main function main(args)
    while true
        scan_ibeacons()
        sleep(5) # Wait before retrying if something goes wrong
    end
end