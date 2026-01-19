using HidApi, LibSerialPort

const VENDOR_ID = 0x04d8
const PRODUCT_ID = 0x00dd
const MCP2221A_PACKET_SIZE = 64
const ULTRASONIC_BAUDRATE = 9600

const SET_GPIO_VALUES = 0x50
const GET_GPIO_VALUES = 0x51
const SET_SRAM_SETTINGS = 0x60
const GET_SRAM_SETTINGS = 0x61
const RESET_CHIP = 0x70

const STATUS_OK = 0x00
const SET_GPIO_AS_OUTPUT = 0x00
const SET_GPIO_AS_INPUT = 0x01
const ENABLE_ALTER_TRUE = 0x80
const ENABLE_ALTER_FALSE = 0x00
const SRAM_GP_AS_INPUT = 0x08
const SRAM_GP_AS_OUTPUT = 0x00

const COMMAND_CODE_INDEX = 1
const STATUS_INDEX = 2
const GP0_ENABLE_DISABLE_PIN_DIRECTION_INDEX = 5
const GP0_PIN_DIRECTION_INDEX = 6
const SRAM_GPIO_CONFIG_INDEX = 8
const SRAM_GP0_SETTING_INDEX = 9
const SRAM_GP1_SETTING_INDEX = 10
const SRAM_GP2_SETTING_INDEX = 11
const SRAM_GP3_SETTING_INDEX = 12

const ULTRASONIC_START_BYTE = 0xFF

function vid_pid(port::String)
    sp = SerialPort(port)
    vid = pid = 0x0000
    try
        trnsprt = LibSerialPort.Lib.sp_get_port_transport(sp)
        if trnsprt == LibSerialPort.SP_TRANSPORT_USB
            vid, pid = LibSerialPort.Lib.sp_get_port_usb_vid_pid(sp) .|> UInt16
            return (vid, pid)
        end
    catch e
        # @error e
    end
    return (vid, pid)
end

function reset_chip(stream)
    buf = zeros(UInt8, MCP2221A_PACKET_SIZE)
    buf[COMMAND_CODE_INDEX] = RESET_CHIP
    buf[2] = 0xAB
    buf[3] = 0xCD
    buf[4] = 0xEF
    write(stream, buf)
    # No response for this command
end

function enable_gpio(stream)
    buf = zeros(UInt8, MCP2221A_PACKET_SIZE)
    buf[COMMAND_CODE_INDEX] = SET_SRAM_SETTINGS
    buf[SRAM_GPIO_CONFIG_INDEX] = ENABLE_ALTER_TRUE
    buf[SRAM_GP0_SETTING_INDEX] = SRAM_GP_AS_INPUT
    buf[SRAM_GP1_SETTING_INDEX] = SRAM_GP_AS_OUTPUT
    buf[SRAM_GP2_SETTING_INDEX] = SRAM_GP_AS_OUTPUT
    buf[SRAM_GP3_SETTING_INDEX] = SRAM_GP_AS_OUTPUT
    write(stream, buf)
    data = read(stream, MCP2221A_PACKET_SIZE)
    return data
end

function get_gpio_values(stream)
    buf = zeros(UInt8, MCP2221A_PACKET_SIZE)
    buf[COMMAND_CODE_INDEX] = GET_GPIO_VALUES
    write(stream, buf)
    data = read(stream, MCP2221A_PACKET_SIZE)
    return data
end

function get_sram_settings(stream)
    buf = zeros(UInt8, MCP2221A_PACKET_SIZE)
    buf[COMMAND_CODE_INDEX] = GET_SRAM_SETTINGS
    write(stream, buf)
    data = read(stream, MCP2221A_PACKET_SIZE)
    return data
end

function find_serial_port(vid::UInt16, pid::UInt16)
    ports = get_port_list()
    for port in ports
        v, p = vid_pid(port)
        if v == vid && p == pid
            return port
        end
    end
    return nothing
end

init()

@info "HID Devices:"
devices = enumerate_devices()
device = find_device(VENDOR_ID, PRODUCT_ID) 
stream = open(device)

@info "Configuring GP0 as input..."
response = enable_gpio(stream)
println("Response: ", response)
@assert response[STATUS_INDEX] == STATUS_OK

@info "Getting SRAM GPIO settings..."
response = get_sram_settings(stream)
println("Response: ", response[23:26])
@assert response[STATUS_INDEX] == STATUS_OK

@info "Getting GPIO values..."
for _ in 1:10
    response = get_gpio_values(stream)
    println("Response: ", response[3:10])
    @assert response[STATUS_INDEX] == STATUS_OK
    sleep(0.5)
end
close(stream)

@info "Read depth..."
port = find_serial_port(UInt16(VENDOR_ID), UInt16(PRODUCT_ID))
@info "Found port: $port"

LibSerialPort.open(port, ULTRASONIC_BAUDRATE) do sp    
    for _ in 1:10
        if read(sp, UInt8) == ULTRASONIC_START_BYTE
            packet = read(sp, 3)            
            if length(packet) == 3
                data_high = packet[1]
                data_low = packet[2]
                checksum_received = packet[3]
                calc_sum = (ULTRASONIC_START_BYTE + data_high + data_low) & 0xFF
                if calc_sum == checksum_received
                    distance = (Int(data_high) << 8) + data_low
                    println("Distance: $(distance) mm")
                else
                    @warn "Checksum mismatch!"
                end
            end
        end
        sleep(0.1) # Small delay
    end
end

shutdown()