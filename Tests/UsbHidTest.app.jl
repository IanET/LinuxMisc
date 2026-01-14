using HidApi, LibSerialPort

const VENDOR_ID = 0x04d8
const PRODUCT_ID = 0x00dd
const GETSTATUS_CMD = 0x10
const MCP2221A_PACKET_SIZE = 64
const STATUS_OK = 0x00

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

init()

devices = enumerate_devices()
device = find_device(VENDOR_ID, PRODUCT_ID) 
stream = open(device)

buf = zeros(UInt8, MCP2221A_PACKET_SIZE)
buf[2] = GETSTATUS_CMD
write(stream, buf)
data = read(stream, MCP2221A_PACKET_SIZE)
println("Data: ", data)
@assert data[1] == 0x10
@assert data[2] == STATUS_OK

ports = get_port_list()
@info "Serial Vid/Pid scan:" [p => vid_pid(p) for p in ports]

close(stream)

shutdown()