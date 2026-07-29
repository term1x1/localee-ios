import SwiftUI

// Ссылка на объект жалобы для .sheet(item:) — голый Int не Identifiable.
struct ReportRef: Identifiable {
    let target: ReportTarget
    let targetId: Int
    var id: String { "\(target.rawValue)-\(targetId)" }
}

// Шторка «пожаловаться». Одна на все виды контента: пост, комментарий,
// сообщение, метка, профиль — отличается только target.
struct ReportSheet: View {
    let target: ReportTarget
    let targetId: Int
    var onDone: (String) -> Void = { _ in }   // текст для всплывашки после отправки

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .spam
    @State private var note = ""
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Пожаловаться")
                    .font(.system(size: 20, weight: .bold)).foregroundColor(Theme.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.text3).padding(8)
                        .background(Theme.bg2).clipShape(Circle())
                }
            }

            Text("Модератор посмотрит и примет решение.")
                .font(.system(size: 14)).foregroundColor(Theme.text3)

            VStack(spacing: 8) {
                ForEach(ReportReason.allCases) { r in
                    Button { reason = r } label: {
                        HStack {
                            Text(r.label)
                                .font(.system(size: 15, weight: reason == r ? .semibold : .regular))
                                .foregroundColor(reason == r ? .white : Theme.text)
                            Spacer()
                            if reason == r {
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(reason == r ? Theme.accent : Theme.bg2)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("Что именно не так? Необязательно", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .font(.system(size: 15))
                .padding(12).background(Theme.bg2)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if !error.isEmpty {
                Text(error).font(.system(size: 13)).foregroundColor(Theme.accent)
            }

            Button(action: send) {
                Text(busy ? "Отправляем…" : "Отправить")
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(busy)

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.bg)
    }

    private func send() {
        guard !busy else { return }
        busy = true
        error = ""
        Task {
            do {
                try await API.shared.report(
                    target: target, id: targetId, reason: reason,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines))
                onDone("Жалоба отправлена")
                dismiss()
            } catch {
                self.error = error.localizedDescription
                busy = false
            }
        }
    }
}
