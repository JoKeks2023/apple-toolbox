# Apple Toolbox

## 1. Vision

**Apple Toolbox** ist eine native Apple-Ecosystem-App und persönliches Technologie-Labor.

Die App soll möglichst viele interessante Apple-Technologien praktisch erfahrbar machen: Frameworks, APIs, Hardwarefunktionen, Capabilities, Entitlements, Systemintegrationen, Developer Tools und spezielle Apple-Technologien.

Die Toolbox ist dabei nicht ausschließlich eine Experiment-App.

Langfristig soll aus den Experimenten eine tatsächlich nützliche persönliche **Apple Utility Toolbox** entstehen.

Die zentrale Frage der App lautet:

> **What can my Apple devices actually do?**

Und die Antwort soll nicht nur aus Dokumentation bestehen:

> **Let's try it.**

---

# 2. Zielplattformen

Die App soll von Anfang an als Multi-Platform-Apple-App entwickelt werden.

## Unterstützte Plattformen

- iPhone / iOS
- iPad / iPadOS
- Mac / macOS
- Apple Watch / watchOS
- Apple TV / tvOS

## Nicht unterstützt

- visionOS / Apple Vision Pro

Die Architektur muss gemeinsame Logik teilen können, darf aber niemals davon ausgehen, dass ein Framework oder eine Hardwarefunktion auf jeder Plattform vorhanden ist.

Jede Plattform bekommt:

- eigene verfügbare Experimente
- eigene Hardware-/Capability-Erkennung
- gegebenenfalls eigene UI
- native SwiftUI-Erfahrung
- plattformspezifische Implementierungen

---

# 3. Grundprinzip

Die Toolbox besteht aus vielen einzelnen **Experimenten**.

Ein Experiment ist möglichst gleichzeitig:

1. eine Demonstration
2. ein Lernmodul
3. ein Debugging-/Diagnostic-Tool
4. eine reale Utility-Funktion, wenn das sinnvoll ist

Beispiel:

Ein NFC-Experiment soll nicht nur anzeigen, dass NFC vorhanden ist.

Es soll später ein tatsächlich brauchbarer NFC Reader/Analyzer werden.

Ein Network-Experiment soll nicht nur `SSID` anzeigen.

Es soll langfristig ein echter Network Inspector werden.

Ein Location-Experiment soll nicht nur Koordinaten ausgeben.

Es soll langfristig als richtiges Location-Dashboard verwendbar sein.

---

# 4. Architektur

Die App soll modular aufgebaut sein.

```text
AppleToolbox/
│
├── Shared/
│   ├── Models/
│   ├── ExperimentRegistry/
│   ├── CapabilitySystem/
│   ├── PermissionSystem/
│   ├── EntitlementSystem/
│   ├── DeviceSystem/
│   └── Services/
│
├── iOS/
├── iPadOS/
├── macOS/
├── watchOS/
└── tvOS/
```

Gemeinsam verwendet werden sollen, wo sinnvoll:

- Datenmodelle
- Experiment Registry
- Capability Registry
- Permission Logic
- Statussystem
- Dokumentations-Metadaten
- Business Logic
- technische Services

Plattformspezifisch bleiben:

- UI
- Hardwarezugriff
- bestimmte Framework-Implementierungen
- Input-Methoden
- Navigation
- bestimmte Experimente

---

# 5. Experiment-Modell

Jedes Experiment soll mindestens beschreiben:

- Name
- Kategorie
- Beschreibung
- Framework
- Plattformen
- Hardwareanforderungen
- OS-Anforderungen
- Permissions
- Capabilities
- Entitlements
- benötigte Apple-Programme
- Availability
- Experiment-Status
- Run/Test-Funktion
- Live Output
- Fehlerzustände
- Apple-Dokumentationslink

Beispiel:

```text
Secure Enclave

Framework:
CryptoKit

Platforms:
iOS
iPadOS
macOS
watchOS

Hardware:
Secure Enclave

Permission:
None

Entitlement:
None

Status:
Available

[Run Experiment]
```

---

# 6. Statussystem

Die Toolbox muss klar zwischen verschiedenen Gründen unterscheiden, warum eine Technologie nicht verfügbar ist.

Mögliche Zustände:

- Available
- Permission Required
- Permission Denied
- Entitlement Required
- Approval Required
- Hardware Unsupported
- OS Unsupported
- Platform Unsupported
- Region Restricted
- Apple Program Required
- Development Only
- Simulator Only
- Device Only
- Not Available

Beispiel:

```text
Corporate Badge

Status:
Entitlement Required

Region:
Supported

Hardware:
Supported

Apple Program:
Required

Development:
Unavailable without entitlement
```

---

# 7. Device Capability Scanner

Die App soll das aktuelle Gerät analysieren.

Mögliche Informationen:

### Hardware

- SoC
- Secure Enclave
- Face ID / Touch ID
- NFC
- UWB
- GPS/GNSS
- accelerometer
- gyroscope
- magnetometer
- barometer
- camera
- depth camera
- LiDAR
- microphone
- speakers
- display features
- Bluetooth
- Wi-Fi
- cellular
- haptics
- game controller support

### Apple Features

- Apple Intelligence availability
- Nearby Interaction
- HomeKit
- Matter
- Wallet
- Apple Pay
- Watch connectivity
- CarPlay
- HealthKit
- MusicKit

Nur öffentlich zuverlässig ermittelbare Informationen verwenden.

---

# 8. Security & Identity

## Authentication

- LocalAuthentication
- Face ID
- Touch ID
- passcode authentication
- biometric availability

## Cryptography

- CryptoKit
- hashing
- symmetric encryption
- asymmetric encryption
- signatures
- verification
- key generation

## Secure storage

- Keychain
- Keychain Sharing
- Secure Enclave
- non-exportable keys

## Application security

- App Attest
- DeviceCheck
- attestation
- integrity experiments

## Identity

- AuthenticationServices
- Passkeys
- WebAuthn
- Sign in with Apple
- credential provider APIs

## Advanced / restricted

- Secure Element
- Access Keys
- Corporate Badge
- Home Key
- Car Key
- Student ID
- Hotel Key
- advanced Wallet credentials

---

# 9. NFC

## Core NFC

- NDEF
- NFC tag reading
- NFC tag writing
- ISO 7816
- ISO 15693
- FeliCa
- MIFARE
- APDU communication
- tag metadata

## Card emulation

- CardSession
- HCE
- APDU handling
- reader detection
- reader lifecycle
- ISO 7816 card emulation

## Advanced Apple NFC

- NFC Wallet passes
- NFC & Secure Element
- Secure Element credentials
- Corporate Badge
- Access Keys

---

# 10. Bluetooth & Accessories

- Core Bluetooth
- BLE scanning
- BLE advertising
- GATT
- services
- characteristics
- notifications
- read/write
- peripheral mode
- central mode
- BLE MIDI
- AccessorySetupKit
- External Accessory
- MFi-related workflows
- accessory discovery

---

# 11. Networking

## Network.framework

- NWConnection
- NWListener
- NWPathMonitor
- TCP
- UDP
- TLS
- service discovery
- Bonjour
- local network
- connectivity state
- interfaces

## Network capabilities

- Access Wi-Fi Information
- Hotspot
- Multicast Networking
- Multipath
- Network Extensions
- Personal VPN
- 5G Network Slicing
- Wireless Accessory Configuration

---

# 12. Wi-Fi

- current network information where publicly available
- SSID/BSSID where permitted
- interface information
- local network permission
- Wi-Fi accessory setup
- hotspot
- network transitions
- connectivity diagnostics

The app must clearly distinguish between information accessible to third-party apps and information available only to Apple's own system tools.

---

# 13. Nearby Interaction / UWB

- Nearby Interaction
- distance
- direction
- relative positioning
- peer sessions
- accessory sessions
- UWB capabilities
- supported advanced spatial-radio APIs

---

# 14. Location

- Core Location
- GPS/GNSS
- altitude
- speed
- course
- heading
- compass
- geofencing
- region monitoring
- visits
- significant location changes
- beacons
- floor level
- indoor location
- authorization states
- precise/approximate location

---

# 15. Indoor

## Indoor Maps

- Indoor Maps concepts
- IMDF
- indoor map visualization
- floors
- indoor POIs
- indoor positioning
- survey concepts

## Indoor Survey-inspired functionality

Create experiments around:

- building import
- IMDF import
- floor visualization
- survey points
- walking paths
- Wi-Fi fingerprints
- heatmaps
- calibration
- confidence
- positioning

The Toolbox should be capable of becoming a practical indoor-survey/analysis utility where Apple publicly exposes the necessary APIs.

---

# 16. Maps

- MapKit
- maps
- annotations
- overlays
- user location
- compass
- search
- POIs
- geocoding
- reverse geocoding
- routing
- ETA
- transport modes
- Look Around
- camera
- 3D maps
- elevation
- indoor maps where available

---

# 17. Home & Matter

## HomeKit

- homes
- rooms
- accessories
- services
- characteristics
- discovery
- state reading
- state changes
- events
- scenes
- automations

## Development

- HomeKit Accessory Simulator
- simulated accessories
- simulated services
- simulated characteristics

## Matter

- Matter
- commissioning
- setup payloads
- accessory discovery
- controller workflows
- Matter devices
- AccessorySetupKit

---

# 18. Camera & Vision

## Camera

- AVFoundation
- photo capture
- video
- microphone
- exposure
- focus
- HDR
- depth
- metadata
- barcode scanning
- camera controls

## Vision

- OCR
- barcode recognition
- face detection
- face landmarks
- human body pose
- hand pose
- object detection
- image classification
- tracking
- document detection
- image analysis

---

# 19. AR / Spatial

## ARKit

- world tracking
- planes
- anchors
- raycasting
- scene reconstruction
- LiDAR
- occlusion
- body tracking
- face tracking
- image tracking
- object-related features
- hand tracking where supported

## RealityKit

- entities
- components
- rendering
- physics
- materials
- animation
- spatial anchors

## RoomPlan

- room scanning
- walls
- doors
- windows
- furniture
- dimensions
- USD/USDZ

---

# 20. AI / ML

## Core ML

- model loading
- inference
- model metadata
- performance
- custom models

## Create ML

- image classification
- object detection
- sound classification
- text classification
- tabular data

## Natural Language

- language identification
- tokenization
- linguistic tagging
- sentiment
- entities
- classification

## Speech

- speech recognition
- transcription
- live speech analysis
- SpeechAnalyzer

## Translation

- language detection
- translation
- translation sessions

## Sound Analysis

- sound classification
- audio events

---

# 21. Apple Intelligence / Foundation Models

Where available:

- Foundation Models
- SystemLanguageModel
- prompts
- structured generation
- `@Generable`
- guided generation
- tool calling
- multimodal input
- model availability
- context/token experiments

Also investigate:

- Core AI
- on-device model deployment
- model import/export
- local model performance

The app should explicitly show whether a feature is:

- unavailable
- device-supported
- Apple Intelligence enabled
- requires a supported OS
- requires internet/PCC
- on-device only

---

# 22. Audio & Media

## AVFoundation

- AVAudioSession
- AVAudioEngine
- recording
- playback
- routing
- mixing
- effects
- taps
- metering
- sample rate
- channels
- latency

## Media

- MediaPlayer
- Now Playing
- AirPlay
- route changes
- Bluetooth audio

## Music

- MusicKit
- Apple Music
- catalog
- library
- playlists
- playback where allowed

## ShazamKit

- song identification
- audio signatures
- custom catalogs

---

# 23. Motion & Sensors

- Core Motion
- accelerometer
- gyroscope
- magnetometer
- device motion
- attitude
- gravity
- user acceleration
- rotation rate
- pedometer
- barometer
- heading

---

# 24. Health

- HealthKit
- workouts
- activity
- heart rate
- sleep
- respiratory data
- mobility
- environmental data
- authorization
- background delivery
- Health Records where permitted

Health features must always respect Apple's health-data restrictions.

---

# 25. Wallet & Payments

## Wallet

- generic passes
- boarding passes
- event tickets
- coupons
- store cards
- membership cards
- gift cards
- pass updates
- location-aware passes
- NFC-enabled passes

## Advanced Wallet

- Corporate Badge
- Home Key
- Car Key
- Student ID
- Hotel Key
- Access Keys
- secure credentials

## Payments

- Apple Pay
- PassKit payment requests
- merchant configuration
- payment authorization
- Tap to Pay where eligible

Advanced credentials must be represented separately from normal Wallet passes and marked with their Apple-program/entitlement requirements.

---

# 26. Notifications & System UI

- UserNotifications
- local notifications
- APNs
- actions
- notification categories
- communication notifications
- Time Sensitive Notifications
- Critical Alerts where eligible
- notification extensions
- Live Activities
- ActivityKit
- Dynamic Island
- widgets
- interactive widgets
- Lock Screen widgets
- StandBy
- Control Center integrations where publicly available

---

# 27. App Intents & Siri

- App Intents
- App Shortcuts
- Siri
- Spotlight
- entities
- queries
- actions
- discoverability
- Apple Intelligence integration

---

# 28. Apple Ecosystem / Continuity

- WatchConnectivity
- Handoff
- Universal Links
- Associated Domains
- Multipeer Connectivity
- SharePlay
- Group Activities
- device-to-device workflows
- AirDrop-related system integration where public

Experiments may be multi-device.

Example:

```text
Mac
 ↕
iPhone
 ↕
iPad
 ↕
Apple Watch
```

---

# 29. Apple Watch

watchOS-specific experiments:

- WatchConnectivity
- motion
- sensors
- health
- haptics
- complications
- widgets
- background execution
- independent watch apps
- interaction with iPhone

The main app should be able to detect a paired Watch when the APIs make that information available.

---

# 30. Apple TV

tvOS-specific experiments:

- HomeKit
- networking
- media
- AVFoundation
- Game Controller
- Siri Remote interactions
- haptics/input where available
- Apple TV-specific UI
- external displays / media workflows where public

The Apple TV build should not simply mirror the iPhone interface.

---

# 31. Mac

macOS-specific experiments:

- Network diagnostics
- Bluetooth
- local networking
- Bonjour
- Metal
- Core Audio
- file system capabilities
- Keychain
- Secure Enclave where supported
- external displays
- game controllers
- media devices
- camera/microphone
- developer-oriented diagnostics

---

# 32. iPad

iPad-specific experiments:

- Apple Pencil where relevant
- multitasking
- Stage Manager
- keyboard/mouse
- external display
- LiDAR where supported
- RoomPlan
- camera
- UWB where supported
- USB accessories
- external hardware

---

# 33. Developer Tools Lab

The project should catalogue and explain useful Apple developer tools, even when those tools are not APIs exposed directly to App Store apps.

Include:

- Xcode
- Simulator
- Devices and Simulators
- Instruments
- Organizer
- Accessibility Inspector
- Create ML
- Reality Composer Pro
- HomeKit Accessory Simulator
- PacketLogger
- Bluetooth tools
- FileMerge
- Console
- Xcode Cloud
- profiling/debugging workflows

---

# 34. Apple Utility / Diagnostic Tools Inspiration

The project should explicitly investigate Apple-created specialized tools and workflows such as:

- Indoor Survey
- AirPort Utility
- Field Test Mode
- Apple Configurator
- Apple Business Manager
- Apple Business Register
- Apple Business Connect
- HomeKit Accessory Simulator
- PacketLogger
- Console
- Instruments

These are inspiration and reference points.

They do not imply that the corresponding private/system APIs can be duplicated by third-party apps.

---

# 35. Capability Registry

Create a centralized registry for Apple capabilities.

Each capability should have:

- display name
- internal key
- platform
- framework
- availability
- managed/unmanaged status
- requestable or not
- Apple documentation
- experiment
- current state

Examples:

- Access WiFi Information
- App Attest
- App Groups
- Apple Pay
- Associated Domains
- AutoFill Credential Provider
- Background Modes
- ClassKit
- Communication Notifications
- Data Protection
- HealthKit
- HomeKit
- Hotspot
- iCloud
- Keychain Sharing
- Maps
- Matter Allow Setup Payload
- Multicast Networking
- Multipath
- Near Field Communication
- Network Extensions
- Personal VPN
- Push Notifications
- Sign in with Apple
- Siri
- Time Sensitive Notifications
- Wallet
- WeatherKit
- Wireless Accessory Configuration
- and all other relevant current Apple capabilities

The registry must distinguish between:

- normal developer capabilities
- managed capabilities
- special entitlements
- Apple programs
- hardware-dependent features

---

# 36. Entitlement Explorer

Provide a dedicated UI for entitlement/capability state.

Example:

```text
Corporate Badge

🟡 Special entitlement

Platform:
iOS

Region:
EEA

Requires:
Apple approval

Current status:
Not provisioned
```

The Toolbox must never attempt to bypass or fake entitlements.

---

# 37. Experiment Engine

Each experiment should support:

- discovery
- permission check
- capability check
- hardware check
- OS check
- optional entitlement check
- run
- live output
- errors
- reset
- documentation

The UI should clearly explain why something does or does not work.

---

# 38. "Why doesn't this work?" system

Every unavailable experiment should provide an explanation.

Example:

```text
RoomPlan

Unavailable

Reason:
This device does not provide LiDAR.

Required:
LiDAR-capable device.
```

Another:

```text
Corporate Badge

Unavailable

Reason:
Required entitlement is not provisioned.

Next step:
Apple approval/program participation required.
```

---

# 39. Multi-Device Experiments

The architecture should allow experiments to use several Apple devices simultaneously.

Examples:

- iPhone ↔ Apple Watch
- iPhone ↔ iPad
- iPhone ↔ Mac
- iPhone ↔ Apple TV
- Mac ↔ iPad
- UWB between supported devices
- Network discovery
- Multipeer Connectivity
- WatchConnectivity

A future experiment may therefore be:

```text
Spatial Link

iPhone
   ↕ UWB
iPad
   ↕ Network
Mac
```

---

# 40. Real Utility Mode

Experiments should eventually be promoted into real tools.

Examples:

### NFC
From:
"Read NFC tag"

To:
"NFC Inspector"

### Networking
From:
"Show current connection"

To:
"Network Inspector"

### Location
From:
"Show coordinates"

To:
"Location Dashboard"

### Audio
From:
"Play sine wave"

To:
"Audio Analyzer"

### HomeKit
From:
"Discover accessories"

To:
"Home Inspector"

### Indoor
From:
"Survey experiment"

To:
"Indoor Mapping / Survey Utility"

### Security
From:
"Generate key"

To:
"Credential / Crypto Lab"

---

# 41. UI Philosophy

The UI should feel:

- native
- clean
- information-dense when useful
- playful
- technically precise
- Apple-like without copying Apple's apps

Primary navigation can use categories.

Each experiment should have a clear:

```text
Status
Requirements
Run
Output
Details
Documentation
```

---

# 42. Initial MVP

The first implementation should NOT attempt the entire specification.

The first version should build the architecture and these experiments:

1. LocalAuthentication
2. CryptoKit
3. Keychain
4. Secure Enclave
5. Core Location
6. Core Motion

The architecture must already support all future categories.

---

# 43. Future Module Roadmap

Suggested order:

### Phase 1
Foundation + Security + Location + Motion

### Phase 2
NFC + Bluetooth + Networking

### Phase 3
UWB + HomeKit + Matter + Accessories

### Phase 4
Camera + Vision + ARKit + RoomPlan

### Phase 5
Audio + MusicKit + ShazamKit

### Phase 6
Maps + Indoor + IMDF

### Phase 7
Wallet + Payments + App Intents + Widgets

### Phase 8
Watch + Continuity + Multi-device

### Phase 9
Health + advanced sensors

### Phase 10
ML + Vision + Speech + Translation + Foundation Models + Core AI

### Phase 11
Special entitlements and Apple programs

### Phase 12
Developer Tools + diagnostic-inspired utilities

---

# 44. Long-Term Product Goal

The final application should feel like:

**Apple Developer Documentation**
+
**Hardware Lab**
+
**API Playground**
+
**Diagnostics**
+
**Network Inspector**
+
**Indoor Survey**
+
**Home Inspector**
+
**Apple Ecosystem Explorer**

in one native Apple application.

The toolbox should continuously answer:

> **What can this Apple device do?**

and, whenever possible:

> **Let's actually use it.**
