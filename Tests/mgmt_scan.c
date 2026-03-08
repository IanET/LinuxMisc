#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
#include <bluetooth/bluetooth.h>
#include <bluetooth/hci.h>

/* Management API Definitions (usually in lib/mgmt.h in BlueZ source) */
#define MGMT_CONTROL_NODE 0
#define HCI_CHANNEL_CONTROL 3

struct mgmt_hdr {
    uint16_t opcode;
    uint16_t index;
    uint16_t len;
} __attribute__((packed));

struct mgmt_ev_device_found {
    struct {
        bdaddr_t bdaddr;
        uint8_t bdaddr_type;
    } addr;
    int8_t rssi;
    uint32_t flags;
    uint16_t eir_len;
    uint8_t eir[0];
} __attribute__((packed));

#define MGMT_OP_START_DISCOVERY 0x0023
#define MGMT_EV_DEVICE_FOUND    0x0012

int main() {
    int sock;
    struct sockaddr_hci addr;
    unsigned char buf[1024];

    // 1. Open a Management Channel socket
    sock = socket(AF_BLUETOOTH, SOCK_RAW | SOCK_CLOEXEC, BTPROTO_HCI);
    if (sock < 0) {
        perror("Socket creation failed");
        return 1;
    }

    memset(&addr, 0, sizeof(addr));
    addr.hci_family = AF_BLUETOOTH;
    addr.hci_dev = HCI_DEV_NONE;
    addr.hci_channel = HCI_CHANNEL_CONTROL; // The magic "mgmt" channel

    if (bind(sock, (struct sockaddr *) &addr, sizeof(addr)) < 0) {
        perror("Bind failed");
        return 1;
    }

    // 2. Start Discovery (Telling the kernel to scan)
    // We send a header + 1 byte for address type (7 = all types)
    struct {
        struct mgmt_hdr hdr;
        uint8_t type;
    } __attribute__((packed)) start_discovery_cmd;

    start_discovery_cmd.hdr.opcode = htobs(MGMT_OP_START_DISCOVERY);
    start_discovery_cmd.hdr.index = htobs(0); // hci0
    start_discovery_cmd.hdr.len = htobs(1);
    start_discovery_cmd.type = 7; 

    if (write(sock, &start_discovery_cmd, sizeof(start_discovery_cmd)) < 0) {
        perror("Write start discovery failed");
    }

    printf("Listening for iBeacons via Management API...\n");

    // 3. Event Loop
    while (1) {
        int len = read(sock, buf, sizeof(buf));
        if (len < sizeof(struct mgmt_hdr)) continue;

        struct mgmt_hdr *hdr = (void *) buf;
        uint16_t opcode = btohs(hdr->opcode);

        if (opcode == MGMT_EV_DEVICE_FOUND) {
            struct mgmt_ev_device_found *ev = (void *) (buf + sizeof(struct mgmt_hdr));
            
            // iBeacon data is inside the EIR (Extended Inquiry Response) buffer
            // We search for the Apple Prefix: 0x4C 0x00 0x02 0x15
            for (int i = 0; i < btohs(hdr->len) - 25; i++) {
                if (ev->eir[i] == 0x4c && ev->eir[i+1] == 0x00 && 
                    ev->eir[i+2] == 0x02 && ev->eir[i+3] == 0x15) {
                    
                    int major = (ev->eir[i+20] << 8) | ev->eir[i+21];
                    int minor = (ev->eir[i+22] << 8) | ev->eir[i+23];

                    char mac[18];
                    ba2str(&ev->addr.bdaddr, mac);
                    printf("[FOUND] %s | Major: %d | Minor: %d | RSSI: %d\n", 
                            mac, major, minor, ev->rssi);
                }
            }
        }
    }

    close(sock);
    return 0;
}