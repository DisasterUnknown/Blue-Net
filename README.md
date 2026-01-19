# Bluetooth Chat App - Offline Mesh Network Communication

A fully offline, decentralized chat application that enables peer-to-peer communication through a Bluetooth mesh network. This application works **100% offline** with no internet connection required, using a gossip protocol to propagate messages across a mesh network of nearby devices.

## Table of Contents

1. [Overview](#overview)
2. [Key Features](#key-features)
3. [Installation](#installation)
4. [Architecture](#architecture)
5. [How It Works](#how-it-works)
6. [Pros and Cons](#pros-and-cons)
7. [Testing and Logs](#testing-and-logs)
8. [Log Types](#log-types)

---

## Overview

This Flutter application implements a **Bluetooth mesh network** for offline communication. It uses:

- **Gossip Protocol**: Probabilistic message propagation with fanout limiting
- **Store-and-Carry (Data Mule)**: Messages are stored and forwarded when devices meet
- **Nearby Connections API**: Android's peer-to-peer Bluetooth communication
- **End-to-End Encryption**: Messages are encrypted before transmission
- **Automatic Peer Discovery**: Devices automatically discover and connect to nearby peers
- **Message Deduplication**: Prevents duplicate message processing
- **TTL-Based Expiration**: Messages expire after 24 hours

### Important: 100% Offline Operation

**This application requires NO internet connection.** All communication happens through Bluetooth Low Energy (BLE) using Android's Nearby Connections API. Devices form a mesh network where messages are propagated from device to device until they reach their destination.

---

## Key Features

- ✅ **Fully Offline**: No internet or cellular connection required
- ✅ **Mesh Networking**: Messages hop between devices to reach destinations
- ✅ **End-to-End Encryption**: Secure message transmission
- ✅ **Automatic Discovery**: Devices automatically find and connect to nearby peers
- ✅ **Store-and-Carry**: Messages are stored and forwarded when devices meet
- ✅ **Message Delivery Receipts**: Track message delivery status
- ✅ **Real-time Logging**: Comprehensive logging system for debugging
- ✅ **Battery-Aware**: Considers device battery levels when selecting peers
- ✅ **Automatic Reconnection**: Reconnects when Bluetooth is turned back on
- ✅ **Duplicate Prevention**: Prevents processing duplicate messages
- ✅ **Periodic Sync**: Syncs data every 10 seconds with connected peers

---

## Installation

### Prerequisites

1. **Flutter SDK**: Version 3.9.2 or higher
2. **FVM (Flutter Version Manager)**: The project uses FVM for Flutter version management
3. **Android Studio** or **VS Code** with Flutter extensions
4. **Android Device**: Physical device with Android 5.0+ (API 21+) for testing
5. **Bluetooth**: Device must support Bluetooth Low Energy (BLE)

### Step-by-Step Installation

#### 1. Clone the Repository

```bash
git clone <repository-url>
cd bluetooth_chat_app
```

#### 2. Install Flutter Dependencies

The project uses FVM. If you don't have FVM installed:

```bash
# Install FVM (if not already installed)
dart pub global activate fvm

# Install Flutter SDK version specified in .fvmrc
fvm install

# Use the Flutter version
fvm use
```

#### 3. Install Project Dependencies

```bash
# Using FVM
fvm flutter pub get

# Or if using system Flutter
flutter pub get
```

#### 4. Android Setup

**Required Permissions** (already configured in `AndroidManifest.xml`):
- `BLUETOOTH`
- `BLUETOOTH_ADMIN`
- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `BLUETOOTH_ADVERTISE`
- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`

**Note**: Location permissions are required for Bluetooth scanning on Android 6.0+.

#### 5. Build and Run

```bash
# Using FVM
fvm flutter run

# Or using system Flutter
flutter run
```

#### 6. Grant Permissions

On first launch, the app will request:
- Bluetooth permissions
- Location permissions (required for Bluetooth scanning)

**Important**: Grant all permissions for the app to function properly.

### Building for Release

```bash
# Android APK
fvm flutter build apk --release

# Android App Bundle
fvm flutter build appbundle --release
```

---

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        UI Layer                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ HomePage │  │ ChatPage │  │ InfoPage │  │ LogsPage │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                     Service Layer                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │GossipService │  │MeshIncident  │  │  MeshService │     │
│  │              │  │SyncService   │  │              │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │LogService    │  │RoutingService│  │UUIDService   │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              Connection Logic Layer                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Gossip Protocol                         │   │
│  │  • Message propagation                               │   │
│  │  • Fanout limiting (3 peers)                         │   │
│  │  • Weighted peer selection                           │   │
│  │  • Duplicate detection                               │   │
│  │  • TTL management                                    │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           Transport Manager                          │   │
│  │  • NearbyTransport (Bluetooth)                       │   │
│  │  • Peer discovery                                    │   │
│  │  • Connection management                             │   │
│  │  • Auto-reconnection                                 │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Storage Layer                           │   │
│  │  • GossipStorageImpl                                 │   │
│  │  • MessageRepository                                 │   │
│  │  • PeerRepository                                    │   │
│  │  • SeenRepository                                    │   │
│  │  • FormRepository                                    │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Data Layer                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  DBHelper    │  │  Models     │  │  Crypto      │     │
│  │  (SQLite)     │  │              │  │  (Encryption)│     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              Platform Layer (Android)                        │
│  • Nearby Connections API                                    │
│  • Bluetooth Low Energy                                      │
│  • Permission Handler                                        │
└─────────────────────────────────────────────────────────────┘
```

### Component Details

#### 1. **Gossip Protocol** (`lib/core/connection-logic/gossip/gossip_protocol.dart`)

The core of the mesh networking system. Implements:

- **Fanout Limiting**: Only gossips to 3 randomly selected peers (configurable)
- **Weighted Selection**: Selects peers based on battery level and signal strength
- **Batched Gossip**: Queues messages and processes them periodically (every 30 seconds)
- **Store-and-Carry**: Stores messages locally and forwards them when new peers connect
- **Duplicate Prevention**: Uses bloom filters and seen message tracking
- **TTL Management**: Messages expire after 24 hours

**Key Configuration**:
- `gossipFanout`: 3 (number of peers to gossip to)
- `gossipInterval`: 30 seconds (how often to process batched messages)
- `maxHops`: 10 (maximum number of hops a message can take)
- `ttlHours`: 24 (time-to-live for messages)

#### 2. **Transport Manager** (`lib/core/connection-logic/transport/transport_manager.dart`)

Manages the underlying transport layer:

- **NearbyTransport**: Uses Android's Nearby Connections API
- **Peer Discovery**: Automatically discovers nearby devices
- **Auto-Connection**: Automatically connects to discovered peers
- **Reconnection**: Automatically reconnects when Bluetooth is turned back on
- **Connection State**: Tracks connected peers and their status

#### 3. **Mesh Incident Sync Service** (`lib/services/mesh_incident_sync_service.dart`)

Handles periodic synchronization:

- **Periodic Sync**: Syncs data every 10 seconds with all connected peers
- **Chat Message Routing**: Forwards chat messages to their destination
- **Delivery Receipts**: Tracks message delivery status
- **Duplicate Detection**: Prevents processing duplicate messages
- **Cleanup**: Periodically cleans up old data (every 30 minutes)

#### 4. **Storage Layer** (`lib/core/connection-logic/storage/`)

Manages local data persistence:

- **MessageRepository**: Stores pending messages for forwarding
- **PeerRepository**: Tracks discovered peers and their metadata
- **SeenRepository**: Tracks seen message IDs to prevent duplicates
- **FormRepository**: Stores form submissions for relay

#### 5. **Database** (`lib/data/data_base/db_helper.dart`)

SQLite database with tables:

- `users`: Stores user information
- `nonUserMsgs`: Stores messages for forwarding (not yet delivered)
- `hashMsgs`: Tracks seen message hashes
- `incident_reports_incoming`: Incoming incident reports
- `incident_reports_outgoing`: Outgoing incident reports
- Chat message tables (encrypted)

---

## How It Works

### Message Flow

#### 1. **Sending a Message**

```
User sends message
    │
    ▼
ChatPage → MeshService.sendNewMessage()
    │
    ▼
1. Encrypt message with recipient's user code
2. Store in local database (nonUserMsgs table)
3. Create GossipPayload.chatMessage()
4. Wrap in GossipMessage with TTL=24h
5. Broadcast via GossipProtocol.broadcastMessage()
    │
    ▼
GossipProtocol._gossipMessageOptimized()
    │
    ▼
1. Select 3 random peers (weighted by battery/signal)
2. Send message to selected peers
3. Track message receipts
    │
    ▼
TransportManager.sendMessage()
    │
    ▼
NearbyTransport.sendBytesPayload()
    │
    ▼
Message sent via Bluetooth to peer devices
```

#### 2. **Receiving a Message**

```
NearbyTransport receives bytes
    │
    ▼
Parse as GossipMessage
    │
    ▼
TransportManager.onMessageReceived stream
    │
    ▼
GossipProtocol._handleIncomingMessage()
    │
    ▼
1. Check if message already seen (duplicate detection)
2. Mark as seen
3. Store for forwarding (store-and-carry)
4. Check message TTL (expire if > 24h)
5. Notify listeners (MeshIncidentSyncService)
    │
    ▼
MeshIncidentSyncService._processIncomingChatMessage()
    │
    ▼
1. Check if message is for this device (receiverUserCode match)
2. If YES:
   - Decrypt and store in chat messages table
   - Send delivery receipt
   - Update stats
3. If NO:
   - Store in nonUserMsgs for forwarding
   - Increment hop count
   - Forward to other peers
```

#### 3. **Store-and-Carry (Data Mule Pattern)**

When a new peer is discovered:

```
Peer discovered
    │
    ▼
GossipProtocol._handlePeerDiscovered()
    │
    ▼
1. Get all pending messages from storage
2. Filter out expired messages (TTL > 24h)
3. Send each pending message to new peer
4. Small delay between messages (50ms) to prevent flooding
```

This allows messages to "hop" between devices even when the sender and receiver are not directly connected.

#### 4. **Periodic Sync**

Every 10 seconds, `MeshIncidentSyncService`:

1. Gets all connected peers
2. For each peer:
   - Syncs new incident reports (not yet sent to this peer)
   - Syncs pending chat messages (not yet delivered)
   - Tracks what has been sent to each peer to avoid duplicates

#### 5. **Gossip Algorithm**

The gossip protocol uses **probabilistic fanout limiting**:

1. **Peer Selection**: From all connected peers, select 3 peers using weighted random selection
   - Weight factors:
     - Battery level: High battery (70-100%) = 2x weight, Low (15-30%) = 0.5x weight
     - Signal strength: Strong (70-100%) = 1.3x weight, Weak (0-30%) = 0.7x weight
2. **Message Propagation**: Send message only to selected peers (not all peers)
3. **Batched Processing**: Queue messages and process them every 30 seconds
4. **Urgent Messages**: Chat messages and incident data are gossiped immediately (not batched)

This reduces network flooding while maintaining good message propagation.

### Encryption

Messages are encrypted using `CryptoHelper`:

- **Encryption Key**: Derived from the recipient's user code
- **Algorithm**: AES encryption (via `encrypt` package)
- **Storage**: Encrypted messages are stored in the database
- **Decryption**: Messages are decrypted when displayed to the recipient

### Duplicate Prevention

Multiple mechanisms prevent duplicate message processing:

1. **Seen Message Tracking**: Each message has a unique ID. Received message IDs are stored in a "seen" table.
2. **Bloom Filter**: Efficiently checks if a message has been seen before.
3. **Database Checks**: Before processing, checks if message already exists in database.
4. **Hop Count**: Messages include a hop count to prevent infinite loops.

### Message Expiration

- **TTL**: Messages have a 24-hour time-to-live
- **Expiration Check**: Before forwarding, messages are checked for expiration
- **Cleanup**: Expired messages are automatically removed from storage

---

## Pros and Cons

### Pros

1. **✅ Fully Offline**: Works without any internet connection
2. **✅ Decentralized**: No central server required
3. **✅ Privacy**: End-to-end encryption for messages
4. **✅ Resilient**: Messages can reach destinations through multiple paths
5. **✅ Battery Efficient**: Fanout limiting and weighted selection reduce battery drain
6. **✅ Automatic**: Auto-discovery and auto-connection of peers
7. **✅ Store-and-Carry**: Messages can be delivered even when sender/receiver are not connected
8. **✅ Scalable**: Gossip protocol scales well with network size
9. **✅ Duplicate Prevention**: Multiple mechanisms prevent duplicate processing
10. **✅ Real-time Logging**: Comprehensive logging for debugging

### Cons

1. **❌ Limited Range**: Bluetooth range is limited (~10-30 meters)
2. **❌ Slow Propagation**: Messages may take time to reach destination (depends on network topology)
3. **❌ No Guaranteed Delivery**: Messages may be lost if network partitions
4. **❌ Battery Drain**: Bluetooth scanning and transmission consume battery
5. **❌ Platform Dependent**: Currently Android-only (Nearby Connections API)
6. **❌ Network Density Required**: Requires multiple devices in proximity for effective mesh
7. **❌ Message Expiration**: Messages expire after 24 hours
8. **❌ No Message Priority**: All messages treated equally (except urgent flag)
9. **❌ Storage Growth**: Store-and-carry mechanism may cause storage growth
10. **❌ Complex Debugging**: Mesh networking can be difficult to debug

---

## Testing and Logs

### Viewing Logs

The application includes a comprehensive logging system accessible from the UI:

1. **Open Logs Page**: Tap the logs icon (📋) in the app bar on the home page
2. **Live Updates**: Logs update in real-time as events occur
3. **Filter by Type**: Logs are color-coded by type (see [Log Types](#log-types))
4. **Copy Logs**: Tap the copy icon to copy all logs to clipboard
5. **Clear Logs**: Tap the delete icon to clear all logs
6. **Pause/Resume**: Tap the pause icon to pause live updates
7. **Auto-scroll**: Toggle auto-scroll to automatically scroll to latest logs

### Log File Location

Logs are stored in a file on the device:

- **Path**: `<app_documents_directory>/app_logs.log`
- **Max Size**: 50 MB (automatically trimmed when exceeded)
- **Format**: Timestamp, log type, and message

### Testing the Application

#### 1. **Basic Testing**

1. Install the app on 2+ Android devices
2. Enable Bluetooth on all devices
3. Grant all required permissions
4. Open the app on all devices
5. Wait for devices to discover each other (check logs)
6. Add a user on Device A
7. Send a message from Device A to Device B
8. Verify message appears on Device B

#### 2. **Mesh Network Testing**

1. Set up 3+ devices in a chain: A → B → C
2. Ensure A and C are not in direct Bluetooth range
3. Send message from A to C
4. Verify message reaches C through B (check hop count in logs)

#### 3. **Store-and-Carry Testing**

1. Send a message from Device A to Device B
2. Turn off Device B before message is delivered
3. Turn on Device C (in range of A)
4. Wait for A and C to connect
5. Turn on Device B (in range of C)
6. Wait for C and B to connect
7. Verify message is delivered to B (carried by C)

#### 4. **Reconnection Testing**

1. Connect two devices
2. Turn off Bluetooth on one device
3. Turn Bluetooth back on
4. Verify devices automatically reconnect (check logs)

#### 5. **Duplicate Prevention Testing**

1. Send a message from Device A to Device B
2. Verify message appears only once on Device B
3. Check logs for duplicate detection messages

#### 6. **Message Expiration Testing**

1. Manually set a message's timestamp to 25 hours ago
2. Verify message is not forwarded (expired)
3. Check logs for expiration messages

### Debugging Tips

1. **Check Logs**: Always check the logs page for detailed information
2. **Peer Discovery**: Verify peers are being discovered (check `NearbyTransport` logs)
3. **Message Flow**: Trace message flow through logs (GossipProtocol → MeshIncidentSync)
4. **Connection Status**: Check connected peers count in Info page
5. **Database**: Use a SQLite browser to inspect the database
6. **Bluetooth State**: Ensure Bluetooth is enabled and permissions are granted

---

## Log Types

The application uses a comprehensive logging system with different log types for different components. Each log type is color-coded in the logs UI for easy identification.

### Log Type Reference

| Log Type | Display Name | Description | When It's Used |
|----------|--------------|-------------|----------------|
| `info` | Info | General informational messages | General app events, initialization |
| `success` | Warning | Success messages (note: display name is "Warning" but used for success) | Successful operations, confirmations |
| `error` | Error | Error messages | Exceptions, failures, critical issues |
| `conflict` | Conflict | Conflict resolution messages | Data conflicts, merge operations |
| `syncManager` | SyncManager | Synchronization manager events | Sync operations, conflict resolution |
| `uploadService` | UploadService | Upload service events | Data upload operations (if implemented) |
| `bluetoothTransport` | BluetoothTransport | Bluetooth transport layer events | Bluetooth connection, scanning, native errors |
| `nearbyTransport` | NearbyTransport | Nearby Connections transport events | Peer discovery, connection, disconnection, message send/receive |
| `wifiDirectTransport` | WiFiDirectTransport | WiFi Direct transport events | WiFi Direct operations (currently not used) |
| `gossipService` | GossipService | Gossip service events | Service initialization, message broadcasting |
| `gossipProtocol` | GossipProtocol | Gossip protocol events | Message propagation, peer selection, fanout, duplicate detection |
| `meshIncidentSync` | MeshIncidentSync | Mesh incident sync events | Periodic sync, message routing, delivery receipts, cleanup |
| `permissionHandler` | PermissionHandler | Permission handling events | Permission requests, grants, denials |
| `bluetoothController` | BluetoothController | Bluetooth controller events | Bluetooth state changes, enable/disable |

### Log Examples

#### NearbyTransport Logs
```
[NearbyTransport]: Started advertising as server - Device name: User_1234567890, Strategy: P2P_CLUSTER
[NearbyTransport]: Started discovery as client - Looking for nearby devices with Service ID: com.example.hackathon
[NearbyTransport]: Peer abc123 connected via TransportType.bluetooth - Total connected: 1
[NearbyTransport]: Successfully sent message msg_123 (256 bytes) to peer abc123
```

#### GossipProtocol Logs
```
[GossipProtocol]: Gossiping message msg_123 to 3 peer(s) (selected from 5 candidates, fanout=3)
[GossipProtocol]: Successfully sent message msg_123 to peer abc123 (weight: 1.50, battery: 85%)
[GossipProtocol]: Received new gossip message msg_123 (type: PayloadType.chatMessage) from peer abc123, hops: 1, TTL: 24h
[GossipProtocol]: Duplicate message msg_123 received from peer abc123, ignoring
```

#### MeshIncidentSync Logs
```
[MeshIncidentSync]: Periodic sync: Syncing incident data and chat messages to 3 connected peer(s)
[MeshIncidentSync]: Received chat message msg_123 from user_001 (for me) via peer abc123
[MeshIncidentSync]: Syncing 5 pending chat message(s) to peer abc123
[MeshIncidentSync]: Cleanup completed: Removed 42 items (hashMsgs: 20, receivedIncidents: 10, oldIncidents: 8, deliveredMsgs: 4)
```

#### Error Logs
```
[Error]: BluetoothTransport initialization failed: Missing permissions
[Error]: Failed to send message msg_123 to peer abc123: Connection lost
[Error]: Error processing incoming chat message from peer abc123: Invalid message format
```

### Understanding Log Messages

1. **Timestamp**: Every log entry includes an ISO 8601 timestamp
2. **Log Type**: Identifies which component generated the log
3. **Message**: Descriptive message about what happened
4. **Context**: Many logs include relevant context (peer IDs, message IDs, counts, etc.)

### Log Analysis Tips

1. **Filter by Type**: Use the color coding to quickly identify log types
2. **Search for Errors**: Look for `[Error]` logs to identify issues
3. **Trace Message Flow**: Follow a message ID through different log types to understand the flow
4. **Check Peer Connections**: Look for `NearbyTransport` logs to verify peer connections
5. **Monitor Sync**: Check `MeshIncidentSync` logs to see periodic sync operations
6. **Debug Gossip**: Use `GossipProtocol` logs to understand message propagation

---

## Additional Notes

### Performance Considerations

- **Fanout Limiting**: Reduces network traffic by limiting gossip to 3 peers
- **Batched Processing**: Queues messages and processes them every 30 seconds
- **Weighted Selection**: Prefers peers with high battery and strong signal
- **Database Indexing**: Indexes on frequently queried columns improve performance
- **Log Trimming**: Logs are automatically trimmed to prevent storage issues

### Security Considerations

- **End-to-End Encryption**: Messages are encrypted before transmission
- **No Central Server**: Decentralized architecture reduces attack surface
- **Permission Handling**: Proper permission requests and handling
- **Secure Storage**: Uses `flutter_secure_storage` for sensitive data

### Future Improvements

- iOS support (requires different transport mechanism)
- Message priority levels
- Group messaging
- File sharing
- Message search
- Offline message queue management
- Network topology visualization
- Message delivery guarantees

---

## License

[Add your license information here]

## Contributors

[Add contributor information here]

---

**Last Updated**: [Current Date]
