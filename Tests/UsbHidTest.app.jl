# sudo /home/pi/.juliaup/bin/julia --project UsbHidTest.app.jl

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

const GP0_ALTER_OUTPUT_VALUE_INDEX = 3
const GP1_ALTER_OUTPUT_VALUE_INDEX = 7
const GP2_ALTER_OUTPUT_VALUE_INDEX = 11
const GP3_ALTER_OUTPUT_VALUE_INDEX = 15

const I2C_SLEEP_TIME = 0.001

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

function write_packet(hiddev::HidDevice, command::UInt8, data_start_index::Int, data::Vector{UInt8})
    @assert data_start_index >= 2
    @assert data_start_index + length(data) - 1 <= MCP2221A_PACKET_SIZE
    buf = zeros(UInt8, MCP2221A_PACKET_SIZE)
    buf[COMMAND_CODE_INDEX] = command
    copyto!(buf, data_start_index, data, 1, length(data))
    write(hiddev, buf)
end

write_packet(hiddev::HidDevice, command::UInt8, data::Vector{UInt8}) = write_packet(hiddev, command, DEFAULT_DATA_START_INDEX, data)
write_packet(hiddev::HidDevice, command::UInt8) = write_packet(hiddev, command, DEFAULT_DATA_START_INDEX, UInt8[])

function reset_chip(hiddev)
    write_packet(hiddev, RESET_CHIP, [0xAB, 0xCD, 0xEF])
    # No response for this command
end

function enable_gpio(hiddev)
    write_packet(hiddev, SET_SRAM_SETTINGS, SRAM_GPIO_CONFIG_INDEX, [
        ENABLE_ALTER_TRUE, 
        SRAM_GP_AS_INPUT, 
        SRAM_GP_AS_OUTPUT, 
        SRAM_GP_AS_OUTPUT, 
        SRAM_GP_AS_OUTPUT])
    data = read(hiddev, MCP2221A_PACKET_SIZE)
    return data
end

function get_gpio_values(hiddev)
    write_packet(hiddev, GET_GPIO_VALUES)
    data = read(hiddev, MCP2221A_PACKET_SIZE)
    return data
end

function get_sram_settings(hiddev)
    write_packet(hiddev, GET_SRAM_SETTINGS)
    data = read(hiddev, MCP2221A_PACKET_SIZE)
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

function set_gpio_1(hiddev, gp1::Bool)
    write_packet(hiddev, SET_GPIO_VALUES, GP1_ALTER_OUTPUT_VALUE_INDEX, [ENABLE_ALTER_TRUE, gp1 ? 0x01 : 0x00])
    data = read(hiddev, MCP2221A_PACKET_SIZE)
    return data
end

const DS2484_I2C_ADDRESS = 0x18
const DS2484_WRITE_BYTE = 0xA5

i2c_addr_to_write_address(addr)::UInt8 = (addr << 1) | 0x00
i2c_addr_to_read_address(addr)::UInt8 = (addr << 1) | 0x01

const I2C_DATA_START_INDEX = 2

const I2C_WRITE_COMMAND = 0x90
const I2C_READ_COMMAND = 0x91
const I2C_READ_DATA_COMMAND = 0x40

const ONEWIRE_RESET_COMMAND = 0xB4
const ONEWIRE_READ_ROM_COMMAND = 0x33
const ONEWIRE_READ_BYTE = 0x96
const ONEWIRE_SET_READ_POINTER = 0xE1
const ONEWIRE_READ_DATA_REGISTER = 0xE1

function i2c_request_read(hiddev, addr, bytes_to_read::UInt16)
    write_packet(hiddev, I2C_READ_COMMAND, [
        UInt8(bytes_to_read % 256),
        UInt8(bytes_to_read ÷ 256),
        i2c_addr_to_read_address(addr)])
    response = read(hiddev, MCP2221A_PACKET_SIZE)
    return response
end

function i2c_read_data(hiddev)
    write_packet(hiddev, I2C_READ_DATA_COMMAND) |> i2c_sleep
    response = read(hiddev, MCP2221A_PACKET_SIZE)
    # @info "I2C Read Data Response $(response[1:4])"
    @assert response[2] == 0x00 # Status OK

    bytes_in_buffer = response[4]
    if bytes_in_buffer <= 60
        return response[5 : 5 + bytes_in_buffer - 1]
    else
        @warn "Buffer error - $bytes_in_buffer"
        return UInt8[]
    end
end


function i2c_write_data(hiddev, addr, i2c_cmd::UInt8, data::Vector{UInt8})
    write_packet(hiddev, I2C_WRITE_COMMAND, I2C_DATA_START_INDEX, [
        UInt8(length(data) + 1),            # Number of bytes to write (data + command)
        0x00,                               # Length High Byte
        i2c_addr_to_write_address(addr),    # 7-bit address + Write bit (0)
        i2c_cmd,                            # I2C command
        data...                             # Remaining data
    ])
    response = read(hiddev, MCP2221A_PACKET_SIZE)
    return response
end

i2c_write_data(hiddev, addr, i2c_cmd) = i2c_write_data(hiddev, addr, i2c_cmd, UInt8[])
ds2484_1wire_reset(hiddev) = i2c_write_data(hiddev, DS2484_I2C_ADDRESS, ONEWIRE_RESET_COMMAND)
ds2484_write_byte(hiddev, byte::UInt8) = i2c_write_data(hiddev, DS2484_I2C_ADDRESS, DS2484_WRITE_BYTE, [byte])
ds2484_read_byte(hiddev) = i2c_write_data(hiddev, DS2484_I2C_ADDRESS, ONEWIRE_READ_BYTE)
ds2484_set_read_pointer(hiddev, pointer::UInt8) = i2c_write_data(hiddev, DS2484_I2C_ADDRESS, ONEWIRE_SET_READ_POINTER, [ONEWIRE_READ_DATA_REGISTER])

const Maybe{T} = Union{T, Nothing}

function i2c_read_byte_from_ds2484(hiddev)::Maybe{UInt8}
    # response = i2c_write_data(hiddev, DS2484_I2C_ADDRESS, ONEWIRE_READ_BYTE) |> i2c_sleep
    response = ds2484_read_byte(hiddev) |> i2c_sleep
    # @info "1Wire Read Byte Command Response $(response[1:2])"
    response = ds2484_set_read_pointer(hiddev, ONEWIRE_READ_DATA_REGISTER) |> i2c_sleep
    # @info "Set Read Pointer Response $(response[1:2])"
    response = i2c_request_and_read(hiddev, DS2484_I2C_ADDRESS, 0x0001) |> i2c_sleep
    if length(response) == 0
        @warn "No data read from 1-Wire device"
        return nothing
    end
    return response[1]
end

function i2c_request_and_read(hiddev, addr, bytes_to_read::UInt16)
    response = i2c_request_read(hiddev, addr, bytes_to_read) |> i2c_sleep
    # @info "I2C Request Read Response $(response[1:2])"
    response = i2c_read_data(hiddev) |> i2c_sleep
    return response
end

function get_temp_sensor_addr(hiddev)
    response = ds2484_1wire_reset(hiddev) |> i2c_sleep
    # @info "Reset response $(response[1:2])"
    response = ds2484_write_byte(hiddev, ONEWIRE_READ_ROM_COMMAND) |> i2c_sleep
    # @info "Read ROM Command Response $(response[1:2])"

    rom_code = UInt8[]
    while length(rom_code) < 8
        byte = i2c_read_byte_from_ds2484(hiddev) |> i2c_sleep
        if byte === nothing; continue end
        # @info "1-Wire Read Byte $([byte])"
        push!(rom_code, byte)
    end

    return rom_code
end

function check_1wire_crc(rom_id::Vector{UInt8})
    # Ensure we have all 8 bytes
    if length(rom_id) != 8
        return false
    end

    crc = 0x00
    for i in 1:8
        byte = rom_id[i]
        for _ in 1:8
            # XOR the LSB of the byte with the LSB of the current CRC
            mix = (crc ^ byte) & 0x01
            crc >>= 1
            if mix != 0
                crc ^= 0x8C  # Apply the polynomial
            end
            byte >>= 1
        end
    end
    
    # If the calculation is correct, the final result of 
    # running all 8 bytes through should be 0.
    return crc == 0x00
end

const TEMPSENSOR_SKIP_ROM_COMMAND = 0xCC
const TEMPSENSOR_CONVERT_T_COMMAND = 0x44
const TEMPSENSOR_READ_SCRATCHPAD_COMMAND = 0xBE

i2c_sleep(x) = (sleep(I2C_SLEEP_TIME); x)

function read_temperature_without_rom_code(hiddev)::Float32
    response = ds2484_1wire_reset(hiddev) |> i2c_sleep
    @info "Reset response $(response[1:2])"
    response = ds2484_write_byte(hiddev, TEMPSENSOR_SKIP_ROM_COMMAND) |> i2c_sleep
    # @info "Skip ROM Command Response $(response[1:2])"
    response = ds2484_write_byte(hiddev, TEMPSENSOR_CONVERT_T_COMMAND) |> i2c_sleep
    # @info "Convert T Command Response $(response[1:2])"
    sleep(0.75) # Wait for conversion
    response = ds2484_1wire_reset(hiddev) |> i2c_sleep
    # @info "Reset response $(response[1:2])"
    response = ds2484_write_byte(hiddev, TEMPSENSOR_SKIP_ROM_COMMAND) |> i2c_sleep
    # @info "Skip ROM Command Response $(response[1:2])"
    response = ds2484_write_byte(hiddev, TEMPSENSOR_READ_SCRATCHPAD_COMMAND) |> i2c_sleep
    @info "Read Scratchpad Command Response $(response[1:2])"

    # scratchpad = UInt8[]
    # while length(scratchpad) < 9
    #     byte = i2c_read_byte_from_ds2484(hiddev) |> i2c_sleep
    #     if byte === nothing; continue end
    #     @info "1-Wire Read Byte $byte"
    #     push!(scratchpad, byte)
    # end
    # temp_lsb = scratchpad[1]
    # temp_msb = scratchpad[2]
    # temp_raw = Int16((temp_msb << 8) | temp_lsb)
    # temperature_c = Float32(temp_raw) * 0.0625

    temp_lsb = i2c_read_byte_from_ds2484(hiddev) |> i2c_sleep |> UInt16
    # @info "Temp LSB: $([temp_lsb])"
    temp_msb = i2c_read_byte_from_ds2484(hiddev) |> i2c_sleep |> UInt16 
    # @info "Temp MSB: $([temp_msb])"
    ds2484_1wire_reset(hiddev) |> i2c_sleep
    temp_raw = Int16((temp_msb << 8) | temp_lsb)
    temperature_c = Float32(temp_raw) / 16.0
    return temperature_c
end

# Read GPIO inputs via HID

HidApi.init()

@info "HID Devices:"
devices = enumerate_devices()
device = find_device(VENDOR_ID, PRODUCT_ID) 
hiddev = open(device)

@info "Configuring GP0 as input..."
response = enable_gpio(hiddev)
println("Response: ", response)
@assert response[STATUS_INDEX] == STATUS_OK

@info "Getting SRAM GPIO settings..."
response = get_sram_settings(hiddev)
println("Response: ", response[23:26])
@assert response[STATUS_INDEX] == STATUS_OK

@info "Getting GPIO values..."
for _ in 1:10
    local response = get_gpio_values(hiddev)
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
response = set_gpio_1(hiddev, true)
@info "Response: $(response[3:18])"
sleep(2)
response = set_gpio_1(hiddev, false)
@info "Response: $(response[3:18])"


@info "Reading ROM code..."
rom_code = get_temp_sensor_addr(hiddev)
@info "1-Wire ROM Code $rom_code"
@assert length(rom_code) == 8
@assert rom_code[1] == 0x28 # DS18B20 family code
@assert check_1wire_crc(rom_code)

round2(x) = round(x, digits=2)
for _ in 1:5
    tempc = read_temperature_without_rom_code(hiddev)
    tempf = (tempc * 9 / 5) + 32 |> round2
    @info "Temperature: $tempc °C, ($tempf °F)"
    sleep(1)
end

# Cleanup HID
close(hiddev)
HidApi.shutdown()