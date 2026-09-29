import Foundation

nonisolated extension ImplementationGuides {
    static let spatial: [String: ImplementationGuide] = [
        "arkit": ImplementationGuide(
            snippet: #"""
            import ARKit
            import RealityKit
            import UIKit

            /// World tracking with plane detection; tap a plane to drop a box on it.
            final class PlacementViewController: UIViewController {
                private let arView = ARView(frame: .zero)

                override func viewDidLoad() {
                    super.viewDidLoad()
                    arView.frame = view.bounds
                    arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    view.addSubview(arView)
                    arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(place(_:))))
                }

                override func viewDidAppear(_ animated: Bool) {
                    super.viewDidAppear(animated)
                    let configuration = ARWorldTrackingConfiguration()
                    configuration.planeDetection = [.horizontal, .vertical]
                    if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                        configuration.sceneReconstruction = .mesh // LiDAR devices only
                    }
                    arView.session.run(configuration)
                }

                override func viewWillDisappear(_ animated: Bool) {
                    super.viewWillDisappear(animated)
                    arView.session.pause()
                }

                @objc private func place(_ gesture: UITapGestureRecognizer) {
                    let point = gesture.location(in: arView)
                    guard let hit = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first else { return }
                    let box = ModelEntity(mesh: .generateBox(size: 0.1), materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)])
                    box.generateCollisionShapes(recursive: false)
                    let anchor = AnchorEntity(world: hit.worldTransform)
                    anchor.addChild(box)
                    arView.scene.addAnchor(anchor)
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSCameraUsageDescription", value: "Uses the camera to place virtual objects in your room."),
            ],
            notes: [
                "Check ARWorldTrackingConfiguration.isSupported (and ARFaceTrackingConfiguration / ARBodyTrackingConfiguration) before offering a mode.",
                "Add arkit to UIRequiredDeviceCapabilities only if the whole app is unusable without ARKit.",
                "ARKit does not run in the Simulator; test on a device.",
            ]
        ),
        "roomplan": ImplementationGuide(
            snippet: #"""
            import RoomPlan
            import UIKit

            /// Shows Apple's scanning UI and exports the finished room as USDZ.
            final class RoomScanViewController: UIViewController {
                private var captureView: RoomCaptureView!

                override func viewDidLoad() {
                    super.viewDidLoad()
                    captureView = RoomCaptureView(frame: view.bounds)
                    captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    captureView.delegate = self
                    view.addSubview(captureView)
                }

                override func viewDidAppear(_ animated: Bool) {
                    super.viewDidAppear(animated)
                    guard RoomCaptureSession.isSupported else { return } // LiDAR required
                    captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
                }

                func finish() { captureView.captureSession.stop() }
            }

            extension RoomScanViewController: @preconcurrency RoomCaptureViewDelegate {
                func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool { true }

                func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
                    print("\(processedResult.walls.count) walls, \(processedResult.doors.count) doors, \(processedResult.objects.count) objects")
                    let url = FileManager.default.temporaryDirectory.appending(path: "Room.usdz")
                    try? processedResult.export(to: url)
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSCameraUsageDescription", value: "Scans your room to build a 3D floor plan."),
            ],
            notes: [
                "RoomPlan needs a LiDAR iPhone or iPad; check RoomCaptureSession.isSupported and hide the feature otherwise.",
                "RoomCaptureViewDelegate inherits NSSecureCoding; the view controller's NSCoding conformance covers it.",
                "Use RoomBuilder with RoomCaptureSession directly for a custom scanning UI.",
            ]
        ),
    ]
}
