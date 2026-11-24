import SwiftUI

/// Drop-in, transparent, interactive SwiftUI canvas hosting one or more squishy LocoRoco blobs.
///
/// Minimal 1-line usage in any SwiftUI app:
/// ```swift
/// LocoBlobSandboxView()
/// ```
/// Or with a `LocoBlobController` you hold yourself:
/// ```swift
/// @State private var blobs = LocoBlobController(
///     blobs: [
///         .init(appearance: .kulche, size: 4),
///         .init(appearance: .priffy, size: 3),
///         .init(appearance: .tupley, size: 2)
///     ],
///     enableGyroscope: true
/// )
///
/// LocoBlobView(controller: blobs)
/// ```
public struct LocoBlobView: View {
    private let controller: LocoBlobController
    private let allowsInteraction: Bool
    private let doubleTapToSplit: Bool

    @State private var isDraggingBlob = false

    public init(
        controller: LocoBlobController,
        allowsInteraction: Bool = true,
        doubleTapToSplit: Bool = true
    ) {
        self.controller = controller
        self.allowsInteraction = allowsInteraction
        self.doubleTapToSplit = doubleTapToSplit
    }

    public var body: some View {
        GeometryReader { proxy in
            let viewSize = proxy.size
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    controller.step(date: timeline.date, viewSize: size)
                    context.withCGContext { cgCtx in
                        cgCtx.saveGState()
                        // Flip Y once so world Y-up matches SwiftUI canvas cleanly
                        cgCtx.translateBy(x: 0, y: size.height)
                        cgCtx.scaleBy(x: 1, y: -1)

                        let s = controller.pointsPerWorldUnit
                        for blob in controller.world.blobs {
                            let vs = controller.visualStates[blob.id] ?? LocoBlobVisualState(blinkTimer: 180)
                            LocoBlobRenderer.draw(
                                blob: blob,
                                in: cgCtx,
                                scale: s,
                                visualState: vs,
                                showDebugMesh: controller.showDebugMesh
                            )
                        }
                        cgCtx.restoreGState()
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                allowsInteraction
                ? DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let worldPt = controller.viewToWorld(value.location, in: viewSize)
                        if !isDraggingBlob {
                            if controller.world.beginDrag(at: worldPt) != nil {
                                isDraggingBlob = true
                            } else {
                                controller.world.poke(at: worldPt)
                            }
                        } else {
                            controller.world.moveDrag(to: worldPt)
                        }
                    }
                    .onEnded { _ in
                        if isDraggingBlob {
                            controller.world.endDrag()
                            isDraggingBlob = false
                        }
                    }
                : nil
            )
            .simultaneousGesture(
                (allowsInteraction && doubleTapToSplit)
                ? SpatialTapGesture(count: 2)
                    .onEnded { value in
                        let worldPt = controller.viewToWorld(value.location, in: viewSize)
                        if let hit = controller.world.blob(at: worldPt, hitPadding: 4.0) {
                            _ = controller.world.split(blobId: hit.id)
                        }
                    }
                : nil
            )
            .onAppear {
                controller.updateContainerSize(viewSize)
            }
        }
    }
}

/// Self-owning convenience wrapper when you don't need to hold a `LocoBlobController` yourself.
public struct LocoBlobSandboxView: View {
    @State private var controller: LocoBlobController
    private let allowsInteraction: Bool
    private let doubleTapToSplit: Bool

    public init(
        blobs: [LocoBlobSeed] = [
            LocoBlobSeed(appearance: .kulche, size: 4),
            LocoBlobSeed(appearance: .priffy, size: 3)
        ],
        pointsPerWorldUnit: CGFloat = LocoBlobConstants.defaultPointsPerWorldUnit,
        enableGyroscope: Bool = false,
        allowsInteraction: Bool = true,
        doubleTapToSplit: Bool = true
    ) {
        _controller = State(initialValue: LocoBlobController(
            blobs: blobs,
            pointsPerWorldUnit: pointsPerWorldUnit,
            enableGyroscope: enableGyroscope
        ))
        self.allowsInteraction = allowsInteraction
        self.doubleTapToSplit = doubleTapToSplit
    }

    public var body: some View {
        LocoBlobView(
            controller: controller,
            allowsInteraction: allowsInteraction,
            doubleTapToSplit: doubleTapToSplit
        )
    }
}
