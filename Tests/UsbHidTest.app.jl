using HidApi

# TBD
const VENDOR_ID = 0x16c0
const PRODUCT_ID = 0x05df

init()

devices = enumerate_devices()
device = find_device(VENDOR_ID, PRODUCT_ID) 
stream = open(device)
data = read(stream)

close(stream)

shutdown()