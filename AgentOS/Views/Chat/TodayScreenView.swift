import SwiftUI

// MARK: - Weather data model

struct TodayWeather {
    let city: String
    let conditionCode: String
    let condition: String
    let temperature: Int
    let temperatureMin: Int?
    let temperatureMax: Int?
    let humidity: Int
    let windSpeed: Int

    var sfSymbol: String {
        switch conditionCode {
        case "Clear", "MostlyClear": return "sun.max.fill"
        case "PartlyCloudy", "MostlyCloudy": return "cloud.sun.fill"
        case "Cloudy", "Overcast": return "cloud.fill"
        case "Drizzle", "Rain", "HeavyRain": return "cloud.rain.fill"
        case "Thunderstorms", "IsolatedThunderstorms", "ScatteredThunderstorms", "StrongStorms": return "cloud.bolt.rain.fill"
        case "Snow", "HeavySnow", "Flurries", "Blizzard", "BlowingSnow": return "cloud.snow.fill"
        case "Sleet", "FreezingRain", "FreezingDrizzle", "WintryMix": return "cloud.sleet.fill"
        case "Haze", "Smoky": return "sun.haze.fill"
        case "Foggy": return "cloud.fog.fill"
        case "Dust", "BlowingDust": return "sun.dust.fill"
        case "Windy", "Breezy": return "wind"
        case "Hot": return "thermometer.sun.fill"
        case "Frigid": return "thermometer.snowflake"
        default: return "cloud.fill"
        }
    }

    var iconColor: Color {
        switch conditionCode {
        case "Clear", "MostlyClear", "Hot": return .orange
        case "Rain", "HeavyRain", "Drizzle", "Thunderstorms", "IsolatedThunderstorms", "ScatteredThunderstorms": return .blue
        case "Snow", "HeavySnow", "Flurries", "Blizzard", "Frigid": return .cyan
        default: return .gray
        }
    }

    var windDirection: String { "NE" } // Simplified, could be extended
}

// MARK: - Today Screen

struct TodayScreenView: View {
    let companionDays: Int?
    let onSuggestionTap: (String) -> Void
    let onChatTap: () -> Void

    @State private var weather: TodayWeather?
    @State private var weatherNoCity: Bool = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<11: return L10n.tr("today.morning")
        case 11..<14: return L10n.tr("today.noon")
        case 14..<18: return L10n.tr("today.afternoon")
        case 18..<23: return L10n.tr("today.evening")
        default: return L10n.tr("today.lateNight")
        }
    }

    private var suggestions: [(icon: String, text: String, message: String)] {
        let hour = Calendar.current.component(.hour, from: Date())
        var items: [(icon: String, text: String, message: String)] = []

        if hour >= 6 && hour <= 10 {
            items.append(("newspaper", L10n.tr("today.suggestNews"), L10n.tr("today.msgNews")))
            items.append(("envelope", L10n.tr("today.suggestEmail"), L10n.tr("today.msgEmail")))
            items.append(("clock", L10n.tr("today.suggestReminder"), L10n.tr("today.msgReminder")))
        } else if hour >= 10 && hour < 14 {
            items.append(("envelope", L10n.tr("today.suggestEmail"), L10n.tr("today.msgEmail")))
            items.append(("clock", L10n.tr("today.suggestReminder"), L10n.tr("today.msgReminder")))
            items.append(("magnifyingglass", L10n.tr("today.suggestSearch"), L10n.tr("today.msgSearch")))
        } else if hour >= 14 && hour < 18 {
            items.append(("clock", L10n.tr("today.suggestReminder"), L10n.tr("today.msgReminder")))
            items.append(("magnifyingglass", L10n.tr("today.suggestSearch"), L10n.tr("today.msgSearch")))
            items.append(("envelope", L10n.tr("today.suggestEmail"), L10n.tr("today.msgEmail")))
        } else {
            items.append(("moon.stars", L10n.tr("today.suggestTomorrow"), L10n.tr("today.msgTomorrow")))
            items.append(("clock", L10n.tr("today.suggestReminder"), L10n.tr("today.msgReminder")))
            items.append(("newspaper", L10n.tr("today.suggestNews"), L10n.tr("today.msgNews")))
        }

        if weatherNoCity {
            if items.count >= 3 {
                items[2] = ("location", L10n.tr("today.setCity"), L10n.tr("today.msgSetCity"))
            }
        }

        // Remove weather suggestion if we already show weather card
        if weather != nil {
            items.removeAll { $0.icon == "sun.max" }
        }

        return Array(items.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 40)

                // Avatar
                AssistantAvatarView(size: .large, state: .happy)

                // Greeting
                VStack(spacing: 6) {
                    Text(greeting)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(L10n.tr("today.question"))
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.textSecondary)

                    if let days = companionDays {
                        Text(L10n.tr("chat.companionDays", ["days": "\(days)"]))
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textBrand)
                            .padding(.top, 2)
                    }
                }

                // Today card (weather + chips in one warm card)
                VStack(alignment: .leading, spacing: 14) {
                    // Weather section
                    if let w = weather {
                        VStack(alignment: .leading, spacing: 10) {
                            // City + date + icon
                            HStack {
                                Text("\(w.city) · \(L10n.tr("today.todayLabel"))")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textTertiary)
                                Spacer()
                                Image(systemName: w.sfSymbol)
                                    .font(.system(size: 28))
                                    .foregroundStyle(w.iconColor)
                            }

                            // Condition + advice
                            Text("\(w.condition)，\(w.temperature)°C")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)

                            // 4-grid stats
                            HStack(spacing: 0) {
                                weatherStat(value: "\(w.temperatureMin ?? w.temperature)°", label: L10n.tr("today.tempMin"))
                                weatherStat(value: "\(w.temperatureMax ?? w.temperature)°", label: L10n.tr("today.tempMax"))
                                weatherStat(value: "\(w.humidity)%", label: L10n.tr("today.humidity"))
                                weatherStat(value: "\(w.windDirection) \(w.windSpeed)", label: L10n.tr("today.wind"))
                            }
                        }

                        Divider()
                            .background(Color(hex: "#F0DECE"))
                    }

                    // Chip suggestions (horizontal wrap)
                    chipSection
                }
                .padding(16)
                .background(Color(hex: "#FFF8F0"))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "#F0DECE"), lineWidth: 1)
                )
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .task {
            await fetchWeather()
        }
    }

    // MARK: - Weather stat cell

    private func weatherStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chip section

    private var chipSection: some View {
        let allChips = suggestions + [("bubble.left", L10n.tr("today.justChat"), "__chat__")]

        return FlowLayout(spacing: 8) {
            ForEach(allChips, id: \.text) { chip in
                Button {
                    if chip.message == "__chat__" {
                        onChatTap()
                    } else {
                        onSuggestionTap(chip.message)
                    }
                } label: {
                    Text(chip.text)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#C4845A"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(hex: "#FFF3E8"))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color(hex: "#F0DECE"), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Fetch weather

    private func fetchWeather() async {
        guard let token = try? await DatabaseService.shared.getSetting(key: "auth_token"),
              !token.isEmpty else { return }

        let baseURL = ServerConfig.shared.httpBaseURL
        guard let url = URL(string: "\(baseURL)/api/today-weather") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let available = json["available"] as? Bool ?? false
                if available {
                    let city = json["city"] as? String ?? ""
                    weather = TodayWeather(
                        city: city,
                        conditionCode: json["conditionCode"] as? String ?? "Clear",
                        condition: json["condition"] as? String ?? "",
                        temperature: json["temperature"] as? Int ?? 0,
                        temperatureMin: json["temperatureMin"] as? Int,
                        temperatureMax: json["temperatureMax"] as? Int,
                        humidity: json["humidity"] as? Int ?? 0,
                        windSpeed: json["windSpeed"] as? Int ?? 0
                    )
                } else {
                    let reason = json["reason"] as? String
                    if reason == "no_city" {
                        weatherNoCity = true
                    }
                }
            }
        } catch {
            print("[TodayScreen] Weather fetch failed: \(error)")
        }
    }
}

// MARK: - Flow Layout (horizontal wrapping)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
