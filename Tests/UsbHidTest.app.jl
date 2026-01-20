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
const DEFAULT_DATA_START_INDEX = 2
const SRAM_GPIO_CONFIG_INDEX = 8

const ULTRASONIC_START_BYTE = 0xFF

const GP1_ALTER_OUTPUT_VALUE_INDEX = 7
# const GP1_OUTPUT_VALUE_INDEX = 8

const I2C_SLEEP_TIME = 0.2

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

function write_packet(stream, command, data_start_index, data::Vector{UInt8})
    @assert data_start_index >= 2
    @assert data_start_index + length(data) - 1 <= MCP2221A_PACKET_SIZE
    buf = zeros(UInt8, MCP2221A_PACKET_SIZE)
    buf[COMMAND_CODE_INDEX] = command
    copy!(buf, data_start_index, data, 1, length(data))
    write(stream, buf)
end

write_packet(stream, command, data::Vector{UInt8}) = write_packet(stream, command, DEFAULT_DATA_START_INDEX, data)
write_packet(stream, command) = write_packet(stream, command, DEFAULT_DATA_START_INDEX, UInt8[])

function reset_chip(stream)
    write_packet(stream, RESET_CHIP, [0xAB, 0xCD, 0xEF])
    # No response for this command
end

function enable_gpio(stream)
    write_packet(stream, SET_SRAM_SETTINGS, SRAM_GPIO_CONFIG_INDEX, [
        ENABLE_ALTER_TRUE, 
        SRAM_GP_AS_INPUT, 
        SRAM_GP_AS_OUTPUT, 
        SRAM_GP_AS_OUTPUT, 
        SRAM_GP_AS_OUTPUT])
    data = read(stream, MCP2221A_PACKET_SIZE)
    return data
end

function get_gpio_values(stream)
    write_packet(stream, GET_GPIO_VALUES)
    data = read(stream, MCP2221A_PACKET_SIZE)
    return data
end

function get_sram_settings(stream)
    write_packet(stream, GET_SRAM_SETTINGS)
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

function set_gpio_1(stream, gp1::Bool)
    write_packet(stream, SET_GPIO_VALUES, GP1_ALTER_OUTPUT_VALUE_INDEX, [ENABLE_ALTER_TRUE, gp1 ? 0x01 : 0x00])
    data = read(stream, MCP2221A_PACKET_SIZE)
    return data
end

const DS2484_I2C_ADDRESS = 0x18
const DS2484_WRITE_BYTE = 0xA5

i2c_addr_to_write_address(addr) = (addr << 1) | 0x00
i2c_addr_to_read_address(addr) = (addr << 1) | 0x01

const I2C_WRITE_COMMAND = 0x90
const I2C_READ_COMMAND = 0x91
const I2C_READ_DATA_COMMAND = 0x40

const 1WIRE_RESET_COMMAND = 0xB4
const 1WIRE_READ_ROM_COMMAND = 0x33
const 1WIRE_READ_BYTE = 0x96

function i2c_request_read(stream, addr, bytes_to_read::UInt16)
    write_packet(stream, I2C_READ_COMMAND, [
        UInt8(bytes_to_read % 256),
        UInt8(bytes_to_read ÷ 256),
        UInt8((addr << 1) | 0x01)])
end

function i2c_read_data(stream)
    write_packet(stream, I2C_READ_DATA_COMMAND)
    sleep(I2C_SLEEP_TIME) # Wait for data to be ready
    # Read the response (64 bytes)
    response = zeros(UInt8, MCP2221A_PACKET_SIZE)
    read(stream, response)
    @assert response[2] == 0x00 # Status OK

    # Byte 2 is the status (0x00 is success)
    # Byte 3 is the internal buffer length
    # Bytes 4 and onwards contain the actual data

    data_end = response[3] + 3
    return response[4:data_end]
end

const I2C_DATA_START_INDEX = 1

function i2c_write_data(stream, addr, i2c_cmd, data::Vector{UInt8})
    write_packet(stream, I2C_WRITE_COMMAND, I2C_DATA_START_INDEX, [
        UInt8(length(data) + 1), # Number of bytes to write (data + command)
        0x00, # No special options
        i2c_addr_to_write_address(addr), # 7-bit address + Write bit (0)
        i2c_cmd, # I2C command
        data # Remaining data
    ])
end

i2c_write_data(stream, addr, i2c_cmd) = i2c_write_data(stream, addr, i2c_cmd, UInt8[])
ds2484_1wire_reset(stream) = i2c_write_data(stream, DS2484_I2C_ADDRESS, 1WIRE_RESET_COMMAND)
ds2484_write_byte(stream, byte::UInt8) = i2c_write_data(stream, DS2484_I2C_ADDRESS, DS2484_WRITE_BYTE, [byte])

function ds2484_read_byte(stream)
    i2c_write_data(stream, DS2484_I2C_ADDRESS, 1WIRE_READ_BYTE)
    sleep(I2C_SLEEP_TIME)
    response = i2c_request_and_read(stream, DS2484_I2C_ADDRESS, 1)
    return response[1]
end

function i2c_request_and_read(stream, addr, bytes_to_read::UInt16)
    i2c_request_read(stream, addr, bytes_to_read)
    sleep(I2C_SLEEP_TIME)
    response = i2c_read_data(stream)
    sleep(I2C_SLEEP_TIME)
    return response
end

function get_temp_sensor_addr(stream)
    ds2484_1wire_reset(stream)
    sleep(I2C_SLEEP_TIME)
    response = i2c_request_and_read(stream, DS2484_I2C_ADDRESS, 1)
    @info "1-Wire Reset Response: $response"
    ds2484_write_byte(stream, 1WIRE_READ_ROM_COMMAND)
    sleep(I2C_SLEEP_TIME)

    rom_code = zeros(UInt8, 8)
    for i in 1:8
        byte = ds2484_read_byte(stream)
        @info "1-Wire Read Byte $i: $(hex(byte))"
        rom_code[i] = byte
    end

    return rom_code
end

# Read GPIO inputs via HID

HidApi.init()

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
    local response = get_gpio_values(stream)
    println("Response: ", response[3:10])
    @assert response[STATUS_INDEX] == STATUS_OK
    sleep(0.5)
end


# Read ultrasonic sensor over serial port

@info "Read depth..."
port = find_serial_port(UInt16(VENDOR_ID), UInt16(PRODUCT_ID))
@info "Found port: $port"

LibSerialPort.open(port, ULTRASONIC_BAUDRATE) do sp    
    for _ in 1:100
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
        sleep(0) 
    end
end

# TODO - Control relays via GPIO outputs
@info "Relay ON/OFF..."
response = set_gpio_1(stream, true)
@info "Response: $(response[3:10])"
sleep(2)
response = set_gpio_1(stream, false)
@info "Response: $(response[3:10])"

# TODO - Read temp over I2C
@info "Read temperature over I2C..."

rom_code = get_temp_sensor_addr(stream)
@info "1-Wire ROM Code: $(join(map(x -> hex(x), rom_code), ", "))"

# Cleanup HID

close(stream)
HidApi.shutdown()