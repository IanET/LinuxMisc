using HidApi, LibSerialPort

const VENDOR_ID = 0x04d8
const PRODUCT_ID = 0x00dd
const MCP2221A_PACKET_SIZE = 64

const SET_GPIO_VALUES = 0x50
const GET_GPIO_VALUES = 0x51
const SET_SRAM_SETTINGS = 0x60
const GET_SRAM_SETTINGS = 0x61
const RESET_CHIP = 0x70
const SET_GPIO_AS_OUTPUT = 0x00
const SET_GPIO_AS_INPUT = 0x01
const STATUS_OK = 0x00
const DONT_ENABLE_ALTER = 0x00
const ENABLE_ALTER = 0x80
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
    buf[SRAM_GPIO_CONFIG_INDEX] = ENABLE_ALTER
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

# function config_gp0_as_input(stream)
#     buf = zeros(UInt8, MCP2221A_PACKET_SIZE)
#     buf[COMMAND_CODE_INDEX] = SET_GPIO_VALUES
#     buf[GP0_ENABLE_DISABLE_PIN_DIRECTION_INDEX] = ENABLE_ALTER
#     buf[GP0_PIN_DIRECTION_INDEX] = SET_GPIO_AS_INPUT
#     write(stream, buf)
#     data = read(stream, MCP2221A_PACKET_SIZE)
#     return data
# end

function get_sram_settings(stream)
    buf = zeros(UInt8, MCP2221A_PACKET_SIZE)
    buf[COMMAND_CODE_INDEX] = GET_SRAM_SETTINGS
    write(stream, buf)
    data = read(stream, MCP2221A_PACKET_SIZE)
    return data
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

# response = config_gp0_as_input(stream)
# println("Response: ", response)
# @assert response[STATUS_INDEX] == STATUS_OK

@info "Getting SRAM GPIO settings..."
response = get_sram_settings(stream)
println("Response: ", response[23:26])
@assert response[STATUS_INDEX] == STATUS_OK

@info "Getting GPIO values..."
response = get_gpio_values(stream)
println("Response: ", response[3:10])
@assert response[STATUS_INDEX] == STATUS_OK

ports = get_port_list()
@info "Serial Vid/Pid scan:" [p => vid_pid(p) for p in ports]

close(stream)

shutdown()