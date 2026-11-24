import LocoBlobKit
import SwiftUI

@main
struct LocoBlobKitDemoApp: App {
    var body: some Scene {
        WindowGroup {
            BlobKitPlaygroundView()
        }
    }
}

struct BlobKitPlaygroundView: View {
    @State private var controller = LocoBlobController(
        blobs: [
            .init(appearance: .kulche, size: 5, normalizedPosition: CGPoint(x: 0.30, y: 0.35)),
            .init(appearance: .priffy, size: 3, normalizedPosition: CGPoint(x: 0.56, y: 0.30)),
            .init(appearance: .tupley, size: 2, normalizedPosition: CGPoint(x: 0.72, y: 0.40)),
            .init(appearance: .pekerone, size: 2, normalizedPosition: CGPoint(x: 0.42, y: 0.22)),
            .init(appearance: .chavez, size: 2, normalizedPosition: CGPoint(x: 0.64, y: 0.20)),
            .init(appearance: .budzi, size: 2, normalizedPosition: CGPoint(x: 0.22, y: 0.25))
        ],
        pointsPerWorldUnit: 4.8,
        enableGyroscope: true
    )

    @State private var selectedAppearance: LocoBlobAppearance = .kulche
    @State private var isJoining = false
    @State private var zeroGravity = false
    @State private var bouncyCard = true
    @State private var expressionIndex = 0

    private let customMint = LocoBlobAppearance.custom(
        color: LocoRGBAColor(r255: 48, g255: 213, b255: 178),
        hair: .tupley,
        face: .kulche
    )

    private var palette: [LocoBlobAppearance] {
        LocoBlobAppearance.classicCast + [customMint]
    }

    private let expressions: [(String, LocoBlobExpression?)] = [
        ("Auto", nil),
        ("Excited", .excited),
        ("Singing", .singing),
        ("Scared", .scared),
        ("Squashed", .squashed)
    ]

    var body: some View {
        ZStack {
            // Soft sky gradient showing off LocoBlobView's transparent background
            LinearGradient(
                colors: [
                    Color(red: 0.78, green: 0.93, blue: 1.0),
                    Color(red: 0.95, green: 0.97, blue: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Floating UI card obstacle that blobs physically collide & bounce off!
            GeometryReader { geo in
                let cardW: CGFloat = min(220, geo.size.width * 0.42)
                let cardH: CGFloat = 54
                let cardRect = CGRect(
                    x: (geo.size.width - cardW) * 0.5,
                    y: geo.size.height * 0.50 - cardH * 0.5,
                    width: cardW,
                    height: cardH
                )

                ZStack {
                    if bouncyCard {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
                            )
                            .overlay(
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.orange)
                                    Text("Bouncy UI Obstacle")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.primary.opacity(0.8))
                                }
                            )
                            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                            .frame(width: cardRect.width, height: cardRect.height)
                            .position(x: cardRect.midX, y: cardRect.midY)
                    }

                    LocoBlobView(controller: controller)
                        .onAppear {
                            syncObstacles(cardRect: cardRect, viewSize: geo.size)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            let w = min(220, newSize.width * 0.42)
                            let r = CGRect(x: (newSize.width - w) * 0.5, y: newSize.height * 0.50 - cardH * 0.5, width: w, height: cardH)
                            syncObstacles(cardRect: r, viewSize: newSize)
                        }
                        .onChange(of: bouncyCard) { _, _ in
                            syncObstacles(cardRect: cardRect, viewSize: geo.size)
                        }
                }
            }
            .ignoresSafeArea()

            // Clean floating HUD controls
            VStack {
                topBar
                Spacer()
                bottomDock
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .statusBarHidden(true)
    }

    private func syncObstacles(cardRect: CGRect, viewSize: CGSize) {
        if bouncyCard {
            controller.setViewSpaceObstacles([cardRect], in: viewSize, isBouncy: true)
        } else {
            controller.world.obstacles = []
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("LocoBlobKit")
                    .font(.caption.weight(.heavy))
                Text("• \(controller.blobCount) blobs (\(controller.totalBlobSize))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button {
                bouncyCard.toggle()
            } label: {
                Image(systemName: bouncyCard ? "rectangle.inset.filled" : "rectangle")
                    .font(.caption.weight(.bold))
                    .padding(8)
                    .background(bouncyCard ? Color.orange.opacity(0.22) : Color.clear, in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
            }

            Button {
                zeroGravity.toggle()
                controller.setGravityMultiplier(zeroGravity ? 0.0 : 1.0)
            } label: {
                Image(systemName: zeroGravity ? "moon.stars.fill" : "arrow.down.circle.fill")
                    .font(.caption.weight(.bold))
                    .padding(8)
                    .background(zeroGravity ? Color.purple.opacity(0.22) : Color.clear, in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
            }

            Button {
                controller.showDebugMesh.toggle()
            } label: {
                Image(systemName: "circle.grid.cross")
                    .font(.caption.weight(.bold))
                    .padding(8)
                    .background(controller.showDebugMesh ? Color.cyan.opacity(0.25) : Color.clear, in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    private var bottomDock: some View {
        VStack(spacing: 8) {
            // Character swatch picker + spawn
            HStack(spacing: 8) {
                ForEach(palette, id: \.self) { style in
                    Button {
                        selectedAppearance = style
                        controller.spawn(style, size: 3)
                    } label: {
                        Circle()
                            .fill(style.bodyColor.swiftUIColor)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle()
                                    .strokeBorder(selectedAppearance == style ? Color.primary : Color.white, lineWidth: selectedAppearance == style ? 2.5 : 1.5)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    controller.jump(charge: 0.9, requireContact: false)
                } label: {
                    Label("Jump", systemImage: "arrow.up")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(.ultraThinMaterial, in: Capsule())

                Button {
                    _ = controller.splitAll()
                } label: {
                    Label("Split", systemImage: "square.grid.2x2")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(.ultraThinMaterial, in: Capsule())

                Button {
                    isJoining.toggle()
                    controller.world.allowCrossAppearanceMerge = false
                    controller.setJoining(isJoining)
                } label: {
                    Label(isJoining ? "Joining…" : "Join", systemImage: "smallcircle.filled.circle")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isJoining ? Color.pink.opacity(0.25) : Color.clear, in: Capsule())
                }
                .background(.ultraThinMaterial, in: Capsule())

                Button {
                    expressionIndex = (expressionIndex + 1) % expressions.count
                    controller.setExpression(expressions[expressionIndex].1)
                } label: {
                    Label(expressions[expressionIndex].0, systemImage: "face.smiling")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}
