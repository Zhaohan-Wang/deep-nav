#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDManager.h>
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

/*
 * 纯 HID 读取桥：按物理设备区分两只外接鼠标（和外接键盘），把原始增量
 * 通过本机 UDP 发给 Godot。系统光标的隐藏/停靠完全由 Godot 进程自己负责——
 * 后台进程调用 CGDisplayHideCursor 对 WindowServer 无效，这里不做任何光标操控。
 */

#define MAX_TRACKED_DEVICES 16
#define ROLE_SLOTS 2

typedef enum { DEVICE_MOUSE = 1, DEVICE_KEYBOARD = 2 } DeviceKind;

typedef struct {
    IOHIDDeviceRef device;
    int slot;
    DeviceKind kind;
    bool built_in;
    uint64_t registry_id;
    char product[160];
} HIDDevice;

typedef struct {
    IOHIDManagerRef manager;
    HIDDevice devices[MAX_TRACKED_DEVICES];
    int socket_fd;
    struct sockaddr_in destination;
    bool include_built_in;
    pid_t parent_pid;
} Bridge;

static Bridge *g_bridge = NULL;

static void json_escape(const char *source, char *target, size_t target_size) {
    size_t write_index = 0;
    for (size_t read_index = 0; source[read_index] != '\0' && write_index + 2 < target_size; read_index++) {
        unsigned char c = (unsigned char)source[read_index];
        if (c == '"' || c == '\\') {
            target[write_index++] = '\\';
            target[write_index++] = (char)c;
        } else if (c >= 0x20) {
            target[write_index++] = (char)c;
        }
    }
    target[write_index] = '\0';
}

static void send_message(Bridge *bridge, const char *message) {
    if (!bridge || bridge->socket_fd < 0) return;
    sendto(bridge->socket_fd, message, strlen(message), 0,
           (const struct sockaddr *)&bridge->destination, sizeof(bridge->destination));
}

static bool cf_boolean_property(IOHIDDeviceRef device, CFStringRef key) {
    CFTypeRef value = IOHIDDeviceGetProperty(device, key);
    return value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)value);
}

static void cf_string_property(IOHIDDeviceRef device, CFStringRef key, char *buffer, size_t size) {
    buffer[0] = '\0';
    CFTypeRef value = IOHIDDeviceGetProperty(device, key);
    if (value && CFGetTypeID(value) == CFStringGetTypeID()) {
        CFStringGetCString((CFStringRef)value, buffer, (CFIndex)size, kCFStringEncodingUTF8);
    }
}

static uint64_t device_registry_id(IOHIDDeviceRef device) {
    uint64_t registry_id = 0;
    io_service_t service = IOHIDDeviceGetService(device);
    if (service) IORegistryEntryGetRegistryEntryID(service, &registry_id);
    return registry_id;
}

static int find_device(Bridge *bridge, IOHIDDeviceRef device) {
    for (int i = 0; i < MAX_TRACKED_DEVICES; i++) {
        if (bridge->devices[i].device == device) return i;
    }
    return -1;
}

static int next_role_slot(Bridge *bridge, DeviceKind kind) {
    bool used[ROLE_SLOTS] = {false, false};
    for (int i = 0; i < MAX_TRACKED_DEVICES; i++) {
        if (bridge->devices[i].kind != kind) continue;
        int slot = bridge->devices[i].slot;
        if (slot >= 0 && slot < ROLE_SLOTS) used[slot] = true;
    }
    for (int slot = 0; slot < ROLE_SLOTS; slot++) {
        if (!used[slot]) return slot;
    }
    return -1;
}

static bool role_slot_in_use(Bridge *bridge, DeviceKind kind, int slot) {
    for (int i = 0; i < MAX_TRACKED_DEVICES; i++) {
        if (bridge->devices[i].device && bridge->devices[i].kind == kind && bridge->devices[i].slot == slot) return true;
    }
    return false;
}

static void device_added(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    (void)result;
    (void)sender;
    Bridge *bridge = (Bridge *)context;
    if (!bridge || find_device(bridge, device) >= 0) return;
    DeviceKind kind = 0;
    if (IOHIDDeviceConformsTo(device, kHIDPage_GenericDesktop, kHIDUsage_GD_Mouse)) kind = DEVICE_MOUSE;
    else if (IOHIDDeviceConformsTo(device, kHIDPage_GenericDesktop, kHIDUsage_GD_Keyboard)) kind = DEVICE_KEYBOARD;
    if (!kind) return;
    bool built_in = cf_boolean_property(device, CFSTR(kIOHIDBuiltInKey));
    /* 内置键盘属于主屏席位 A；内置触控板不占用两只外接鼠标的席位。 */
    if (built_in && kind == DEVICE_MOUSE && !bridge->include_built_in) return;
    int index = -1;
    for (int i = 0; i < MAX_TRACKED_DEVICES; i++) {
        if (!bridge->devices[i].device) { index = i; break; }
    }
    if (index < 0) return;
    HIDDevice *entry = &bridge->devices[index];
    /* 一把物理外接键盘/接收器可能暴露多个 Keyboard HID interface。它们必须共同
       组成逻辑席位 B，不能因为第一个接口占了 slot 1 就丢弃真正发送按键的接口。 */
    int role_slot = kind == DEVICE_KEYBOARD ? (built_in ? 0 : 1) : next_role_slot(bridge, kind);
    if (role_slot < 0 || (kind == DEVICE_MOUSE && role_slot_in_use(bridge, kind, role_slot))) return;
    entry->device = device;
    entry->kind = kind;
    entry->built_in = built_in;
    entry->slot = role_slot;
    entry->registry_id = device_registry_id(device);
    cf_string_property(device, CFSTR(kIOHIDProductKey), entry->product, sizeof(entry->product));
    if (entry->product[0] == '\0') snprintf(entry->product, sizeof(entry->product), kind == DEVICE_MOUSE ? "HID Mouse" : "HID Keyboard");
    char escaped[320];
    char message[640];
    json_escape(entry->product, escaped, sizeof(escaped));
    snprintf(message, sizeof(message),
             "{\"type\":\"device\",\"kind\":\"%s\",\"connected\":true,\"slot\":%d,\"built_in\":%s,\"id\":%llu,\"product\":\"%s\"}",
             kind == DEVICE_MOUSE ? "mouse" : "keyboard", entry->slot, entry->built_in ? "true" : "false",
             (unsigned long long)entry->registry_id, escaped);
    send_message(bridge, message);
}

static void device_removed(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    (void)result;
    (void)sender;
    Bridge *bridge = (Bridge *)context;
    int index = bridge ? find_device(bridge, device) : -1;
    if (index < 0) return;
    HIDDevice *entry = &bridge->devices[index];
    char escaped[320];
    char message[640];
    json_escape(entry->product, escaped, sizeof(escaped));
    snprintf(message, sizeof(message),
             "{\"type\":\"device\",\"kind\":\"%s\",\"connected\":false,\"slot\":%d,\"built_in\":%s,\"id\":%llu,\"product\":\"%s\"}",
             entry->kind == DEVICE_MOUSE ? "mouse" : "keyboard", entry->slot, entry->built_in ? "true" : "false",
             (unsigned long long)entry->registry_id, escaped);
    send_message(bridge, message);
    memset(entry, 0, sizeof(*entry));
    entry->slot = -1;
}

static void input_value(void *context, IOReturn result, void *sender, IOHIDValueRef value) {
    (void)result;
    (void)sender;
    Bridge *bridge = (Bridge *)context;
    IOHIDElementRef element = IOHIDValueGetElement(value);
    IOHIDDeviceRef device = IOHIDElementGetDevice(element);
    int index = bridge ? find_device(bridge, device) : -1;
    if (index < 0 || bridge->devices[index].slot < 0) return;
    int slot = bridge->devices[index].slot;
    DeviceKind kind = bridge->devices[index].kind;
    uint32_t usage_page = IOHIDElementGetUsagePage(element);
    uint32_t usage = IOHIDElementGetUsage(element);
    CFIndex integer_value = IOHIDValueGetIntegerValue(value);
    char message[256];
    if (kind == DEVICE_MOUSE && usage_page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_X && integer_value != 0) {
        snprintf(message, sizeof(message), "{\"type\":\"motion\",\"slot\":%d,\"dx\":%ld,\"dy\":0}", slot, (long)integer_value);
        send_message(bridge, message);
    } else if (kind == DEVICE_MOUSE && usage_page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Y && integer_value != 0) {
        snprintf(message, sizeof(message), "{\"type\":\"motion\",\"slot\":%d,\"dx\":0,\"dy\":%ld}", slot, (long)integer_value);
        send_message(bridge, message);
    } else if (kind == DEVICE_MOUSE && usage_page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Wheel && integer_value != 0) {
        snprintf(message, sizeof(message), "{\"type\":\"wheel\",\"slot\":%d,\"delta\":%ld}", slot, (long)integer_value);
        send_message(bridge, message);
    } else if (kind == DEVICE_MOUSE && usage_page == kHIDPage_Button && usage >= 1 && usage <= 8) {
        snprintf(message, sizeof(message), "{\"type\":\"button\",\"slot\":%d,\"button\":%u,\"pressed\":%s}",
                 slot, usage, integer_value ? "true" : "false");
        send_message(bridge, message);
    } else if (kind == DEVICE_KEYBOARD && usage_page == kHIDPage_KeyboardOrKeypad && usage >= 4 && usage <= 231) {
        snprintf(message, sizeof(message), "{\"type\":\"key\",\"slot\":%d,\"id\":%llu,\"usage\":%u,\"pressed\":%s}",
                 slot, (unsigned long long)bridge->devices[index].registry_id,
                 usage, integer_value ? "true" : "false");
        send_message(bridge, message);
    }
}

static void stop_bridge(int signal_number) {
    (void)signal_number;
    if (g_bridge && g_bridge->manager) IOHIDManagerClose(g_bridge->manager, kIOHIDOptionsTypeNone);
    CFRunLoopStop(CFRunLoopGetMain());
}

static void parent_watchdog(CFRunLoopTimerRef timer, void *context) {
    (void)timer;
    Bridge *bridge = (Bridge *)context;
    if (!bridge || bridge->parent_pid <= 1) return;
    if (kill(bridge->parent_pid, 0) != 0 && errno == ESRCH) {
        CFRunLoopStop(CFRunLoopGetMain());
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s UDP_PORT [--include-built-in]\n", argv[0]);
        return 64;
    }
    int port = atoi(argv[1]);
    if (port <= 0 || port > 65535) return 64;
    Bridge bridge;
    memset(&bridge, 0, sizeof(bridge));
    bridge.parent_pid = getppid();
    for (int i = 0; i < MAX_TRACKED_DEVICES; i++) bridge.devices[i].slot = -1;
    bridge.include_built_in = argc >= 3 && strcmp(argv[2], "--include-built-in") == 0;
    bridge.socket_fd = socket(AF_INET, SOCK_DGRAM, 0);
    bridge.destination.sin_family = AF_INET;
    bridge.destination.sin_port = htons((uint16_t)port);
    bridge.destination.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bridge.socket_fd < 0) return 70;
    bridge.manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!bridge.manager) return 70;
    int usage_page = kHIDPage_GenericDesktop;
    int mouse_usage = kHIDUsage_GD_Mouse;
    int keyboard_usage = kHIDUsage_GD_Keyboard;
    CFNumberRef page_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage_page);
    CFNumberRef mouse_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &mouse_usage);
    CFNumberRef keyboard_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &keyboard_usage);
    const void *keys[] = {CFSTR(kIOHIDDeviceUsagePageKey), CFSTR(kIOHIDDeviceUsageKey)};
    const void *mouse_values[] = {page_number, mouse_number};
    const void *keyboard_values[] = {page_number, keyboard_number};
    CFDictionaryRef mouse_matching = CFDictionaryCreate(kCFAllocatorDefault, keys, mouse_values, 2,
                                                         &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionaryRef keyboard_matching = CFDictionaryCreate(kCFAllocatorDefault, keys, keyboard_values, 2,
                                                            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    const void *matching_values[] = {mouse_matching, keyboard_matching};
    CFArrayRef matching = CFArrayCreate(kCFAllocatorDefault, matching_values, 2, &kCFTypeArrayCallBacks);
    IOHIDManagerSetDeviceMatchingMultiple(bridge.manager, matching);
    IOHIDManagerRegisterDeviceMatchingCallback(bridge.manager, device_added, &bridge);
    IOHIDManagerRegisterDeviceRemovalCallback(bridge.manager, device_removed, &bridge);
    IOHIDManagerRegisterInputValueCallback(bridge.manager, input_value, &bridge);
    IOHIDManagerScheduleWithRunLoop(bridge.manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    IOReturn open_result = IOHIDManagerOpen(bridge.manager, kIOHIDOptionsTypeNone);
    char ready[192];
    snprintf(ready, sizeof(ready), "{\"type\":\"ready\",\"ok\":%s,\"code\":%d}", open_result == kIOReturnSuccess ? "true" : "false", open_result);
    send_message(&bridge, ready);
    CFRelease(matching);
    CFRelease(mouse_matching);
    CFRelease(keyboard_matching);
    CFRelease(page_number);
    CFRelease(mouse_number);
    CFRelease(keyboard_number);
    if (open_result != kIOReturnSuccess) return 77;
    g_bridge = &bridge;
    signal(SIGINT, stop_bridge);
    signal(SIGTERM, stop_bridge);
    CFRunLoopTimerContext watchdog_context = {0, &bridge, NULL, NULL, NULL};
    CFRunLoopTimerRef watchdog = CFRunLoopTimerCreate(kCFAllocatorDefault,
                                                      CFAbsoluteTimeGetCurrent() + 0.25,
                                                      0.25, 0, 0, parent_watchdog, &watchdog_context);
    if (watchdog) CFRunLoopAddTimer(CFRunLoopGetMain(), watchdog, kCFRunLoopDefaultMode);
    CFRunLoopRun();
    if (watchdog) {
        CFRunLoopTimerInvalidate(watchdog);
        CFRelease(watchdog);
    }
    close(bridge.socket_fd);
    CFRelease(bridge.manager);
    return 0;
}
