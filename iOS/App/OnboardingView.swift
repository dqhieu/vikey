import SwiftUI

/// Three steps: what Vikey does, add the keyboard in Settings, try it.
struct OnboardingView: View {
    var done: () -> Void
    @State private var page = startPage
    @State private var added = KeyboardStatus.isAdded
    @Environment(\.scenePhase) private var phase

    private static var startPage: Int {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-OnbPage"), i + 1 < a.count, let n = Int(a[i + 1]) { return n }
        return 0
    }

    var body: some View {
        ZStack {
            Glow()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    intro.tag(0)
                    addKeyboard.tag(1)
                    tryIt.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                Button {
                    if page < 2 { withAnimation { page += 1 } } else { done() }
                } label: {
                    Text(page == 0 ? LocalizedStringKey("Bắt đầu") : page == 1 ? (added ? LocalizedStringKey("Tiếp tục") : LocalizedStringKey("Để sau")) : LocalizedStringKey("Xong"))
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(LinearGradient(colors: [Color.brand, Color(red: 0.24, green: 0.30, blue: 0.80)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.brand.opacity(0.35), radius: 12, y: 6)
                }
                .padding(.horizontal, 24).padding(.bottom, 12)
            }
        }
        .onChange(of: phase) { _, p in if p == .active { added = KeyboardStatus.isAdded } }
    }

    private var width: CGFloat { UIScreen.main.bounds.width }

    private var intro: some View {
        VStack(spacing: 22) {
            Spacer()
            Image("Logo").resizable().frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.brand.opacity(0.3), radius: 14, y: 6)
            VStack(spacing: 10) {
                Text("Tự chuyển Anh/Việt\nkhi bạn gõ").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("Gõ tiếng Anh giữa câu tiếng Việt, Vikey tự sửa và chuyển chế độ cho bạn.")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            DemoCard().padding(.top, 8)
            Spacer(); Spacer()
        }
        .padding(.horizontal, 24).frame(width: width)
    }

    private var addKeyboard: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("Thêm bàn phím Vikey").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 16) {
                Step(n: 1, text: "Mở Cài đặt của Vikey")
                Step(n: 2, text: "Chọn Bàn phím")
                Step(n: 3, text: "Bật Vikey")
                Step(n: 4, text: "Bật Cho phép Truy cập đầy đủ để rung khi gõ (không bắt buộc)")
            }
            Button { KeyboardStatus.openSettings() } label: {
                Label("Mở Cài đặt", systemImage: "gear").font(.headline)
            }
            .buttonStyle(.bordered).tint(Color.brand)
            if added {
                Label("Đã thêm Vikey", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
            }
            Text("Vikey chỉ dùng Truy cập đầy đủ để rung khi gõ phím và cho ✨. Những gì bạn gõ không rời khỏi máy, trừ đoạn chữ bạn chọn rồi chạm ✨ để viết lại: đoạn đó được gửi tới Claude của Anthropic bằng khoá API bạn nhập trong ứng dụng.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer(); Spacer()
        }
        .padding(.horizontal, 28).frame(width: width, alignment: .leading)
    }

    @State private var sample = ""
    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("Thử ngay").font(.largeTitle.bold())
            Text("Chạm vào ô bên dưới, giữ 🌐 để chọn Vikey, rồi gõ thử \"tooi ddi meeting nhes\".")
                .foregroundStyle(.secondary)
            TextField("Gõ ở đây", text: $sample, axis: .vertical)
                .lineLimit(3...6)
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.brand.opacity(0.3)))
            Spacer(); Spacer()
        }
        .padding(.horizontal, 28).frame(width: width, alignment: .leading)
    }
}

private struct Step: View {
    let n: Int, text: LocalizedStringKey
    var body: some View {
        HStack(spacing: 14) {
            Text("\(n)").font(.headline).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(Color.brand, in: Circle())
            Text(text).font(.title3).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Slow breathing brand glow behind the onboarding.
struct Glow: View {
    var body: some View {
        TimelineView(.animation) { t in
            let s = sin(t.date.timeIntervalSinceReferenceDate / 3)
            ZStack {
                Color(.systemGroupedBackground)
                Circle().fill(Color.brand.opacity(0.22)).frame(width: 420).blur(radius: 90)
                    .offset(x: 120 + s * 30, y: -260 + s * 20)
                Circle().fill(Color(red: 0.36, green: 0.55, blue: 1).opacity(0.16)).frame(width: 360).blur(radius: 90)
                    .offset(x: -140 - s * 25, y: 280)
            }
        }
        .ignoresSafeArea()
    }
}
