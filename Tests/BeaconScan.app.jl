using Sockets, UUIDs

@info "Scanning for iBeacons using Julia mgmt API..." 

# Requires root 

const AF_BLUETOOTH = 31
const BTPROTO_HCI = 1
const HCI_CHANNEL_CONTROL = 3
const HCI_DEV_NONE = 0xffff

const MGMT_EV_CMD_STATUS  = 0x0002
const MGMT_EV_DEVICE_FOUND = 0x0012
const MGMT_EV_DISCOVERING = 0x0013

const MGMT_OP_START_DISCOVERY = 0x0107
const MGMT_OP_STOP_DISCOVERY = 0x0007

function uuid_from_bytes(vb::Vector{UInt8})
    @assert length(vb) == 16 "UUID must be 16 bytes"
    v1 = UInt32(vb[1]) << 24 | UInt32(vb[2]) << 16 | UInt32(vb[3]) << 8 | UInt32(vb[4])
    v2 = UInt32(vb[5]) << 24 | UInt32(vb[6]) << 16 | UInt32(vb[7]) << 8 | UInt32(vb[8])
    v3 = UInt32(vb[9]) << 24 | UInt32(vb[10]) << 16 | UInt32(vb[11]) << 8 | UInt32(vb[12])
    v4 = UInt32(vb[13]) << 24 | UInt32(vb[14]) << 16 | UInt32(vb[15]) << 8 | UInt32(vb[16])
    return UUID((v1, v2, v3, v4))
end

hex(bytes::Vector{UInt8}) = join(string.(bytes, base=16, pad=2), "")
hex(byte::UInt8) = string(byte, base=16, pad=2)
hex(word::UInt16) = string(word, base=16, pad=4)

function parse_manufacturer_data(data::Vector{UInt8})
    company_id = UInt16(data[2]) << 8 | UInt16(data[1])
    if company_id == 0x004C && data[3] == 0x02 && data[4] == 0x15
        uuid = uuid_from_bytes(data[5:20])
        major = UInt16(data[21]) << 8 | UInt16(data[22])
        minor = UInt16(data[23]) << 8 | UInt16(data[24])
        tx_power = UInt8(data[25])
        @info "iBeacon Detected | UUID: $uuid | Major: $major | Minor: $minor | Tx Power: $tx_power dBm"
    else 
        @info "Unknown Manufacturer Data | Company ID: $(hex(company_id)) | Data: $(hex(data[3:end]))"
    end
end

function parse_payload(payload::Vector{UInt8})
    address = join(string.(reverse(payload[1:6]), base=16, pad=2), ":")
    @info "Device Found | Address: $address"
    # @info "Payload: $(hex(payload[15:end]))"
    i = 15
    while i <= length(payload)
        adlen = payload[i]
        if adlen == 0; break; end
        adtype = payload[i+1]
        addata = payload[i+2:i+adlen]
        if adtype == 0xFF
            parse_manufacturer_data(addata)
        else
            @info "AD Structure | Type: $(hex(adtype)) | Data: $(hex(addata))"
        end
        i += 1 + adlen
    end
end

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
            event = UInt16(buffer[2]) << 8 | buffer[1]
            index = UInt16(buffer[4]) << 8 | buffer[3]
            payload_len = UInt16(buffer[6]) << 8 | buffer[5]

            @info "Event: $event | Index: $index | Payload Length: $payload_len bytes"

            if event == MGMT_EV_DEVICE_FOUND
                parse_payload(buffer[7:end])
            elseif event == MGMT_EV_DISCOVERING
                opcode = UInt16(buffer[8]) << 8 | buffer[7]
                @info "Discovering State Changed | Opcode: $opcode"
                if opcode == MGMT_OP_START_DISCOVERY
                    @info "Starting"
                elseif opcode == MGMT_OP_STOP_DISCOVERY
                    @info "Stopping"
                    close(io)
                    return
                end
            elseif event == MGMT_EV_CMD_STATUS
                opcode = UInt16(buffer[8]) << 8 | buffer[7]
                status = buffer[9]
                @info "Command Status | Opcode: $opcode | Status: $status"
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