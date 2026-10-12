import SwiftUI

struct WatchPasscodeView: View {
    let title: String
    let message: String?
    let retryAfter: Date?
    let onSubmit: (String) -> Void
    @State private var digits = ""
    private let keys = [1, 2, 3, 4, 5, 6, 7, 8, 9, -1, 0, -2]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { position in
                        Image(systemName: position < digits.count ? "circle.fill" : "circle")
                            .font(.system(size: 9))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("已輸入 \(digits.count) 位，共 4 位")

                if let retryAfter {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if retryAfter > context.date {
                            Text("請等 \(Int(ceil(retryAfter.timeIntervalSince(context.date)))) 秒")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if let message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                    ForEach(keys, id: \.self) { key in
                        if key == -1 {
                            Color.clear.frame(height: 32).accessibilityHidden(true)
                        } else {
                            Button {
                                enter(key)
                            } label: {
                                Group {
                                    if key == -2 {
                                        Image(systemName: "delete.left")
                                    } else {
                                        Text(String(key)).font(.title3.monospacedDigit())
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(.gray.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(key == -2 ? "刪除上一位" : String(key))
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .onDisappear { digits = "" }
    }

    private func enter(_ key: Int) {
        if key == -2 {
            if !digits.isEmpty { digits.removeLast() }
        } else if digits.count < 4 {
            digits.append(String(key))
            if digits.count == 4 {
                let pin = digits
                digits = ""
                onSubmit(pin)
            }
        }
    }
}

struct WatchLockView: View {
    @Environment(WatchPasscodeLockService.self) private var lock
    @State private var message: String?

    var body: some View {
        WatchPasscodeView(
            title: "輸入解鎖密碼",
            message: message,
            retryAfter: lock.retryAfter
        ) { pin in
            do {
                try lock.unlock(pin: pin)
                message = nil
            } catch {
                message = error.localizedDescription
            }
        }
        .onDisappear { message = nil }
    }
}
