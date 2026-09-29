import Foundation

nonisolated extension ImplementationGuides {
    static let input: [String: ImplementationGuide] = [
        "game-controller": ImplementationGuide(
            snippet: #"""
            import GameController

            /// Picks up connected controllers and reacts to buttons and thumbsticks.
            @MainActor
            final class ControllerInput {
                private var task: Task<Void, Never>?

                func start() {
                    GCController.controllers().forEach(configure)
                    task = Task { [weak self] in
                        for await notification in NotificationCenter.default.notifications(named: .GCControllerDidConnect) {
                            if let controller = notification.object as? GCController { self?.configure(controller) }
                        }
                    }
                }

                private func configure(_ controller: GCController) {
                    guard let gamepad = controller.extendedGamepad else { return }
                    // Handlers run on controller.handlerQueue (main by default).
                    gamepad.buttonA.pressedChangedHandler = { _, _, pressed in
                        if pressed { print("Jump") }
                    }
                    gamepad.leftThumbstick.valueChangedHandler = { _, x, y in
                        print("Move", x, y)
                    }
                }

                func stop() { task?.cancel() }
            }
            """#,
            infoPlist: [
                .init(key: "GCSupportsControllerUserInteraction", value: "<true/>"),
                .init(key: "GCSupportedGameControllers", value: "<array><dict><key>ProfileName</key><string>ExtendedGamepad</string></dict></array>"),
            ],
            capabilities: ["Game Controllers"],
            notes: [
                "Pair controllers in Settings › Bluetooth; startWirelessControllerDiscovery() is only needed for MFi pairing flows.",
                "Per-frame games can poll gamepad state (e.g. controller.capture() or reading values in the render loop) instead of using handlers.",
                "GCVirtualController shows on-screen touch controls when no hardware controller is connected.",
            ]
        ),
    ]
}
