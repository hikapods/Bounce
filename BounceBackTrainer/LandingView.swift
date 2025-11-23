import SwiftUI

struct LandingView: View {
    @State private var showDemo = false
    @State private var showAdvanced = false

    var body: some View {
        ZStack {
            // Background gradient
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

                // Top row
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

                // Hero section
                VStack(spacing: 16) {
                    Text("Train like a pro,\nfrom any goal.")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)

                    Text("Bounce Back Trainer tracks your shots on a marked target and gives you instant accuracy feedback on your phone.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Stat pills
                HStack(spacing: 16) {
                    StatPill(title: "Impact error", value: "0.18 m")
                    StatPill(title: "Shots analyzed", value: "24")
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                // Buttons
                VStack(spacing: 12) {

                    Button(action: {
                        showDemo = true
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
        .sheet(isPresented: $showDemo) {
            NavigationStack {
                ContentView()
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAdvanced) {
            NavigationStack {
                ContentView()
            }
            .preferredColorScheme(.dark)
        }
        .preferredColorScheme(.dark)
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
