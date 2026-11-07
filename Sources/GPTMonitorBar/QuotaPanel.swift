import AppKit
import QuotaCore
import SwiftUI

struct MenuBadge: View {
    let text: String
    let level: BadgeLevel
    let stale: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 6) {
            BrandMark(size: 13)
            Text(text)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(stale ? .secondary : .primary)
            Circle()
                .fill(PanelStyle.accent(for: stale ? .unknown : level, in: scheme))
                .frame(width: 4, height: 4)
        }
        .padding(.leading, 4).padding(.trailing, 7)
        .frame(height: 19)
        .background {
            Capsule().fill(reduceTransparency
                ? Color(nsColor: .windowBackgroundColor)
                : Color.primary.opacity(scheme == .dark ? 0.10 : 0.055))
        }
        .overlay { Capsule().strokeBorder(.primary.opacity(0.10), lineWidth: 0.5) }
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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var resetsExpanded = false

    private var accent: Color { PanelStyle.accent(in: scheme) }
    private var warning: Color { PanelStyle.accent(for: .caution, in: scheme) }

    var body: some View {
        VStack(spacing: 16) {
            header
            ViewThatFits(in: .vertical) {
                content.fixedSize(horizontal: false, vertical: true)
                ScrollView { content }
            }
            .frame(maxHeight: 430)
            footer
        }
        .padding(20)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.primary)
        .tint(accent)
        .background { PanelBackground() }
    }

    private var header: some View {
        HStack(spacing: 11) {
            BrandMark(size: 34)
            VStack(alignment: .leading, spacing: 5) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { title; planLabel }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) { title; planLabel }
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.failure != nil ? warning : store.updatedAt != nil ? accent : .secondary)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(updateText)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button(action: refresh) {
                Group {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium))
                    }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(QuietButtonStyle(cornerRadius: 16))
            .disabled(store.isRefreshing)
            .accessibilityLabel("立即刷新")
            .help("立即刷新")
        }
    }

    private var title: some View {
        Text("ChatGPT · Codex").font(.system(size: 16, weight: .semibold)).fixedSize()
    }

    @ViewBuilder private var planLabel: some View {
        if let plan = store.planType {
            Text(plan.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.primary.opacity(0.045), in: .rect(cornerRadius: 5))
                .help(plan)
        }
    }

    private var updateText: String {
        if store.isRefreshing { return "正在更新额度…" }
        if store.failure != nil { return store.snapshot == nil ? "暂时无法读取额度" : "数据待更新" }
        guard let updated = store.updatedAt else { return "等待额度数据" }
        return "上次更新 \(updated.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()))"
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let failure = store.failure { failureNotice(failure) }
            if let snapshot = store.snapshot {
                ForEach(snapshot.groups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        if snapshot.groups.count > 1 || group.id != "codex" {
                            Text(group.title)
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
                        }
                        ForEach(Array(group.windows.enumerated()), id: \.offset) { _, window in
                            QuotaCard(window: window)
                        }
                    }
                }
                if snapshot.groups.isEmpty { unavailableState }
                accountSection(snapshot)
            } else if store.failure == nil {
                QuotaPlaceholder(title: "5 小时额度")
                QuotaPlaceholder(title: "周额度")
            }
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 22, weight: .light)).accessibilityHidden(true)
            Text("套餐额度暂不可用").font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity).padding(.vertical, 28)
        .quotaSurface()
    }

    private func failureNotice(_ failure: QuotaFailure) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14)).foregroundStyle(warning).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(failure.description)
                if store.snapshot != nil {
                    Text("当前显示上次成功读取的数据").foregroundStyle(.secondary)
                    if let updated = store.updatedAt {
                        Text("上次更新 \(panelDate(updated))").foregroundStyle(.secondary)
                    }
                }
                if [.missingCLI, .launchFailed, .disconnected, .invalidResponse].contains(failure) {
                    Button("选择 Codex…", action: chooseCLI).buttonStyle(.link)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12)).padding(14)
        .quotaSurface()
    }

    private func accountSection(_ snapshot: QuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                    resetsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.counterclockwise").foregroundStyle(.secondary).frame(width: 16)
                    Text("可用重置")
                    Spacer(minLength: 8)
                    Text(snapshot.resetCount.map { "\($0) 次" } ?? "暂不可用")
                        .fontWeight(.semibold).monospacedDigit()
                        .foregroundStyle(snapshot.resetCount == nil ? Color.secondary : Color.primary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(resetsExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .contentShape(.rect)
            }
            .buttonStyle(QuietButtonStyle(cornerRadius: 0, restingOpacity: 0))
            .accessibilityLabel("可用重置")
            .accessibilityValue(
                (snapshot.resetCount.map { "\($0) 次" } ?? "暂不可用") + (resetsExpanded ? "，已展开" : "，已折叠")
            )
            if resetsExpanded {
                resetDetails(snapshot).padding(.horizontal, 16).padding(.bottom, 14)
            }
            Divider().padding(.horizontal, 16)
            HStack(spacing: 9) {
                Image(systemName: "creditcard").foregroundStyle(.secondary).frame(width: 16)
                Text("额外额度")
                Spacer(minLength: 8)
                Text(snapshot.extraCredits ?? "暂不可用")
                    .fontWeight(.semibold).monospacedDigit().multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(snapshot.extraCredits == nil ? Color.secondary : Color.primary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .font(.system(size: 12))
        .quotaSurface()
        .clipShape(.rect(cornerRadius: 16))
    }

    private func resetDetails(_ snapshot: QuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let credits = snapshot.resetCredits, !credits.isEmpty {
                ForEach(credits) { credit in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(credit.title).fixedSize()
                            Spacer(minLength: 0)
                            Text(expirationText(credit)).foregroundStyle(.secondary).fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(credit.title)
                            Text(expirationText(credit)).foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(snapshot.resetCount == 0 ? "暂无可用重置" : "重置明细暂不可用")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11).monospacedDigit())
    }

    private func expirationText(_ credit: ResetCredit) -> String {
        credit.expiration.map { "\(panelDate($0)) 到期" } ?? "到期时间暂不可用"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: manageUsage) {
                HStack(spacing: 6) {
                    Text("管理用量")
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
            }
            .buttonStyle(QuietButtonStyle())
            .help("在 ChatGPT 网页管理额度与重置")
            HStack(spacing: 7) {
                Toggle("开机自启动", isOn: Binding(
                    get: { launchAtLogin.isRegistered },
                    set: { launchAtLogin.setRegistered($0) }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                Text("开机自启动").accessibilityHidden(true)
                Spacer()
                Button("退出", action: quit).buttonStyle(.plain).padding(.vertical, 3)
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            if let error = launchAtLogin.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if launchAtLogin.needsApproval {
                Button(action: launchAtLogin.openSettings) {
                    Label("等待系统批准 · 打开登录项设置", systemImage: "exclamationmark.circle")
                        .font(.system(size: 11)).foregroundStyle(warning)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct QuotaCard: View {
    let window: QuotaWindow
    @Environment(\.colorScheme) private var scheme

    private var accent: Color {
        let level: BadgeLevel
        if let remaining = window.remainingPercent {
            level = remaining <= 20 ? .low : remaining <= 50 ? .caution : .healthy
        } else {
            level = .unknown
        }
        return PanelStyle.accent(for: level, in: scheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(window.title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 8)
                Text("剩余额度").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(window.remainingPercent.map(String.init) ?? "—")
                    .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                if window.remainingPercent != nil {
                    Text("%").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(window.usagePercent.map { "已用 \($0)%" } ?? "暂不可用")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(window.remainingPercent.map { "剩余 \($0)%" } ?? "余量暂不可用")
            GeometryReader { geometry in
                Capsule().fill(.primary.opacity(0.07))
                if let remaining = window.remainingPercent, remaining > 0 {
                    Capsule().fill(accent)
                        .frame(width: geometry.size.width * CGFloat(remaining) / 100)
                }
            }
            .frame(height: 6).accessibilityHidden(true)
            resetDetails
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quotaSurface()
    }

    private var resetDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("自动重置").foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let resetAt = window.resetAt {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text(countdown(until: resetAt, now: context.date)).foregroundStyle(accent)
                    }
                }
            }
            .font(.system(size: 11).monospacedDigit())
            Text(window.resetAt.map(panelDate) ?? "时间暂不可用")
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct QuotaPlaceholder: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text("—").font(.system(size: 32, weight: .semibold, design: .rounded))
            Capsule().fill(.primary.opacity(0.07)).frame(height: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text("正在读取套餐额度…").font(.system(size: 11))
                Text("恢复时间待更新").font(.system(size: 12))
            }
        }
        .foregroundStyle(.secondary).padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quotaSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，等待额度数据")
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
