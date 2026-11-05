import AppKit
import QuotaCore
import SwiftUI

private let ink = Color(red: 0.06, green: 0.08, blue: 0.13)
private let teal = Color(red: 0.36, green: 0.90, blue: 0.80)
private let blue = Color(red: 0.37, green: 0.69, blue: 1)
private let amber = Color(red: 1, green: 0.73, blue: 0.37)
private let coral = Color(red: 1, green: 0.46, blue: 0.52)
private let muted = Color(red: 0.65, green: 0.72, blue: 0.81)

struct MenuBadge: View {
    let text: String
    let level: BadgeLevel
    let stale: Bool

    private static let mark: NSImage? = {
        let resource = Bundle.main.url(forResource: "ChatGPTMark", withExtension: "png")
            ?? Bundle.module.url(forResource: "ChatGPTMark", withExtension: "png")
        return resource.flatMap(NSImage.init(contentsOf:))
    }()

    private var colors: [Color] {
        if stale { return [.gray.opacity(0.85), .gray] }
        switch level {
        case .healthy: return [teal, blue]
        case .caution: return [amber, .orange]
        case .low: return [coral, Color(red: 0.9, green: 0.36, blue: 0.71)]
        case .unknown: return [.gray.opacity(0.85), .gray]
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if let mark = Self.mark {
                    Image(nsImage: mark).resizable().scaledToFit()
                } else {
                    Image(systemName: "sparkle").font(.system(size: 9))
                        .foregroundStyle(.black).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white, in: .rect(cornerRadius: 3))
                }
            }
            .frame(width: 14, height: 14)
            Text(text)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(ink)
        }
        .padding(.leading, 5).padding(.trailing, 9)
        .frame(height: 19)
        .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), in: .capsule)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

struct QuotaPanel: View {
    let store: QuotaStore
    let launchAtLogin: LaunchAtLogin
    let refresh: () -> Void
    let chooseCLI: () -> Void
    let manageUsage: () -> Void
    let quit: () -> Void
    @State private var resetsExpanded = false

    var body: some View {
        VStack(spacing: 14) {
            header
            ViewThatFits(in: .vertical) {
                content.fixedSize(horizontal: false, vertical: true)
                ScrollView { content }
            }
            .frame(maxHeight: 430)
            footer
        }
        .padding(18)
        .frame(width: 428)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white)
        .background {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.15, blue: 0.23), ink, ink],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 42, height: 42)
                .background(LinearGradient(colors: [teal, blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: .rect(cornerRadius: 13))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text("ChatGPT · Codex").font(.system(size: 19, weight: .bold))
                    if let plan = store.planType {
                        Text(plan.uppercased())
                            .font(.system(size: 9, weight: .bold)).tracking(0.6)
                            .foregroundStyle(teal)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(teal.opacity(0.12), in: .capsule)
                    }
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.failure != nil ? amber : store.updatedAt != nil ? teal : muted)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    if let updated = store.updatedAt {
                        Text("上次更新 \(updated.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()))")
                    } else {
                        Text(store.isRefreshing ? "正在读取套餐额度…" : "等待额度数据")
                    }
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(muted)
            }
            Spacer(minLength: 6)
            Button(action: refresh) {
                Group {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .semibold))
                    }
                }
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.07), in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .accessibilityLabel("立即刷新")
            .help("立即刷新")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let failure = store.failure {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(amber)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(failure.description)
                        if store.snapshot != nil {
                            Text("当前显示上次成功读取的数据").foregroundStyle(muted)
                        }
                        if [.missingCLI, .launchFailed, .disconnected, .invalidResponse].contains(failure) {
                            Button("选择 Codex…", action: chooseCLI).buttonStyle(.link).tint(blue)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12))
                .padding(12)
                .quotaSurface()
            }
            if let snapshot = store.snapshot {
                ForEach(snapshot.groups) { group in
                    if snapshot.groups.count > 1 || group.id != "codex" {
                        Text(group.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(muted)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(group.windows.enumerated()), id: \.offset) { _, window in
                            QuotaCard(window: window, compact: group.windows.count > 1)
                        }
                    }
                }
                if snapshot.groups.isEmpty {
                    Text("套餐额度暂不可用")
                        .font(.system(size: 13)).foregroundStyle(muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .quotaSurface()
                }
                resetSection(snapshot)
                HStack {
                    Label("额外额度", systemImage: "creditcard")
                        .foregroundStyle(muted)
                    Spacer()
                    Text(snapshot.extraCredits ?? "暂不可用")
                        .fontWeight(.semibold).monospacedDigit()
                }
                .font(.system(size: 12))
                .padding(.horizontal, 13).padding(.vertical, 10)
                .quotaSurface()
            }
        }
    }

    private func resetSection(_ snapshot: QuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                resetsExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(ink)
                        .frame(width: 23, height: 23).background(blue, in: .circle)
                    Text("可用重置").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(snapshot.resetCount.map { "\($0) 次" } ?? "暂不可用")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(snapshot.resetCount == nil ? muted : teal)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.07), in: .capsule)
                    Image(systemName: resetsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(muted)
                }
                .padding(.horizontal, 13).padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("可用重置")
            .accessibilityValue(
                (snapshot.resetCount.map { "\($0) 次" } ?? "暂不可用") + (resetsExpanded ? "，已展开" : "，已折叠")
            )

            if resetsExpanded {
                Divider().overlay(.white.opacity(0.08))
                VStack(alignment: .leading, spacing: 9) {
                    if let credits = snapshot.resetCredits, !credits.isEmpty {
                        ForEach(credits) { credit in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(credit.title).fontWeight(.medium)
                                Spacer(minLength: 6)
                                Text(credit.expiration.map { "\(panelDate($0)) 到期" } ?? "到期时间暂不可用")
                                    .foregroundStyle(muted).monospacedDigit()
                            }
                        }
                    } else {
                        Text(snapshot.resetCount == 0 ? "暂无可用重置" : "重置明细暂不可用")
                            .foregroundStyle(muted)
                    }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 13).padding(.vertical, 11)
            }
        }
        .quotaSurface()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Toggle("开机自启动", isOn: Binding(
                    get: { launchAtLogin.isRegistered },
                    set: { launchAtLogin.setRegistered($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(teal)
                Text("开机自启动").foregroundStyle(muted).accessibilityHidden(true)
                Spacer()
                Button(action: manageUsage) {
                    Label("管理用量", systemImage: "arrow.up.right")
                        .fontWeight(.semibold)
                        .foregroundStyle(blue)
                }
                .buttonStyle(.plain)
                .help("在 ChatGPT 网页管理额度与重置")
                Spacer()
                Button("退出", action: quit)
                    .foregroundStyle(muted)
                    .buttonStyle(.plain)
            }
            .font(.system(size: 12))

            if let error = launchAtLogin.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(amber)
            } else if launchAtLogin.needsApproval {
                Button(action: launchAtLogin.openSettings) {
                    Label("等待系统批准 · 打开登录项设置", systemImage: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(amber)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 1)
    }
}

private struct QuotaCard: View {
    let window: QuotaWindow
    let compact: Bool

    private var accent: Color {
        guard let remaining = window.remainingPercent else { return muted }
        if remaining <= 20 { return coral }
        if remaining <= 50 { return amber }
        return teal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 23, height: 23)
                    .background(accent.opacity(0.12), in: .rect(cornerRadius: 7))
                    .accessibilityHidden(true)
                Text(window.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if let used = window.usagePercent {
                    Text("已用 \(used)%")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(muted)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.white.opacity(0.07), in: .capsule)
                        .fixedSize()
                }
            }

            if compact {
                ring.frame(maxWidth: .infinity)
                resetDetails
            } else {
                HStack(spacing: 14) {
                    ring.frame(width: 116)
                    resetDetails
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [accent.opacity(0.08), .clear],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .quotaSurface()
    }

    private var ring: some View {
        let size: CGFloat = compact ? 66 : 78
        return ZStack {
            Circle().strokeBorder(.white.opacity(0.10), lineWidth: 5)
            if let remaining = window.remainingPercent, remaining > 0 {
                Circle().inset(by: 2.5).trim(from: 0, to: Double(remaining) / 100)
                    .stroke(accent.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accent.opacity(0.22), radius: 4)
            }
            VStack(spacing: 1) {
                Text(window.remainingPercent.map { "\($0)%" } ?? "—")
                    .font(.system(size: compact ? 19 : 22, weight: .bold).monospacedDigit())
                Text(window.remainingPercent == nil ? "暂不可用" : "剩余额度")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(muted)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.remainingPercent.map { "剩余 \($0)%" } ?? "余量暂不可用")
    }

    private var resetDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("自动重置", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(muted)
            if let resetAt = window.resetAt {
                Text(panelDate(resetAt))
                    .font(.system(size: compact ? 13 : 17, weight: .semibold).monospacedDigit())
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(countdown(until: resetAt, now: context.date))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(accent)
                }
            } else {
                Text("时间暂不可用").font(.system(size: 12)).foregroundStyle(muted)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, compact ? 9 : 13)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ink.opacity(0.4), in: .rect(cornerRadius: 10))
    }
}

private func countdown(until target: Date, now: Date) -> String {
    let remaining = target.timeIntervalSince(now)
    guard remaining > 0 else { return "等待服务更新" }
    let minutes = Int(ceil(remaining / 60))
    let days = minutes / 1_440
    let hours = minutes / 60 % 24
    if days > 0 { return "还有 \(days) 天 \(hours) 小时" }
    if hours > 0 { return "还有 \(hours) 小时 \(minutes % 60) 分钟" }
    return "还有 \(minutes) 分钟"
}

private func panelDate(_ date: Date) -> String {
    date.formatted(
        .dateTime.month(.defaultDigits).day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            .locale(Locale(identifier: "zh_CN"))
    )
}

private extension View {
    func quotaSurface() -> some View {
        background(.white.opacity(0.055), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.09))
                    .allowsHitTesting(false)
            }
    }
}

private extension QuotaFailure {
    var description: String {
        switch self {
        case .missingCLI: "未找到 Codex CLI。"
        case .launchFailed: "无法启动 Codex CLI，请检查安装路径。"
        case .signInRequired: "请在终端运行 codex login，并使用 ChatGPT 账号登录后刷新。"
        case .timedOut: "读取额度超时，请重试。"
        case .disconnected: "Codex 连接已断开，请重试。"
        case .invalidResponse: "暂时无法解析额度数据。"
        case .requestFailed: "Codex 未能读取套餐额度，请重试。"
        }
    }
}
