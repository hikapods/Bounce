//
//  LandingView.swift
//  BounceBackTrainer
//
//  Created by Mahika Patil on 12/4/25.
//

import SwiftUI

struct LandingView: View {
    @State private var showMain = false
    @State private var showAdvanced = false

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    Color(red: 0.05, green: 0.07, blue: 0.12)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                HStack {
                    Text("Bounce Back")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Text("Beta")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .padding(.horizontal)
                .padding(.top, 12)

                Spacer(minLength: 0)

                VStack(spacing: 16) {
                    Text("Train like a pro,\nfrom any goal.")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("Bounce Back Trainer tracks your shots on a marked target and gives you instant accuracy feedback on your phone.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                HStack(spacing: 16) {
                    StatPill(title: "Impact error", value: "0.18 m")
                    StatPill(title: "Shots analyzed", value: "24")
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                VStack(spacing: 12) {
                    Button(action: {
                        showMain = true
                    }) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                            Text("Start Demo")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(radius: 12, y: 6)
                    }
                    .padding(.horizontal, 32)

                    Button(action: {
                        showAdvanced = true
                    }) {
                        Text("Advanced tools")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.top, 4)
                    }
                }

                Spacer()

                Text("On-device vision • No hardware • Prototype build")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showMain) {
            NavigationStack {
                ContentView()
            }
            .preferredColorScheme(ColorScheme.dark)
        }
        .sheet(isPresented: $showAdvanced) {
            AdvancedToolsView()
                .preferredColorScheme(ColorScheme.dark)
        }
        .preferredColorScheme(ColorScheme.dark)
    }
}

struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct AdvancedToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var stats = ShotStatsManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack(spacing: 16) {
                    ScoreStatCard(
                        title: "Total shots",
                        value: "\(stats.totalShots)"
                    )

                    ScoreStatCard(
                        title: "On-target %",
                        value: stats.totalShots == 0
                            ? "–"
                            : String(format: "%.0f%%", stats.hitRate * 100.0)
                    )

                    ScoreStatCard(
                        title: "Avg error",
                        value: {
                            if let avg = stats.averageErrorMeters {
                                return String(format: "%.2f m", avg)
                            } else {
                                return "–"
                            }
                        }()
                    )
                }

                if stats.shots.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "soccerball")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No shots logged yet.")
                            .foregroundColor(.secondary)
                        Text("Run a session in Live Camera to start collecting data.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("Recent shots") {
                            ForEach(stats.shots) { shot in
                                HStack {
                                    Image(systemName: shot.isHit ? "checkmark.circle.fill" : "xmark.circle")
                                        .foregroundColor(shot.isHit ? .green : .red)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(shot.isHit ? "On target" : "Miss")
                                            .font(.subheadline.weight(.semibold))
                                        if let error = shot.distanceMeters {
                                            Text(String(format: "Error: %.2f m", error))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Text(shot.date, style: .time)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Shot stats")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct ScoreStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title2.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ShotRecord: Identifiable {
    let id = UUID()
    let date: Date
    let isHit: Bool
    let distanceMeters: Double?
}

final class ShotStatsManager: ObservableObject {
    static let shared = ShotStatsManager()

    @Published private(set) var shots: [ShotRecord] = []

    var totalShots: Int {
        shots.count
    }

    var hitRate: Double {
        guard totalShots > 0 else { return 0 }
        let hits = shots.filter { $0.isHit }.count
        return Double(hits) / Double(totalShots)
    }

    var averageErrorMeters: Double? {
        let errors = shots.compactMap { $0.distanceMeters }
        guard !errors.isEmpty else { return nil }
        let sum = errors.reduce(0, +)
        return sum / Double(errors.count)
    }

    private init() {}

    func registerShot(isHit: Bool, distanceMeters: Double?) {
        let record = ShotRecord(
            date: Date(),
            isHit: isHit,
            distanceMeters: distanceMeters
        )
        shots.insert(record, at: 0)

        if shots.count > 100 {
            shots.removeLast(shots.count - 100)
        }
    }
}

