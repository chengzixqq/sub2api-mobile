import SwiftUI
import Sub2Core

struct ListFieldEditor<Field: ListField>: View {
    let title: String
    @Binding var selection: ListFieldSelection<Field>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(selection.orderedFields, id: \.rawValue) { field in
                        HStack(spacing: 4) {
                            Toggle(field.title, isOn: Binding(
                                get: { selection.isEnabled(field) },
                                set: { selection.setEnabled($0, for: field) }))
                                .accessibilityIdentifier("list-fields.\(Field.storageNamespace).\(field.rawValue)")
                            moveButton(field, direction: -1)
                            moveButton(field, direction: 1)
                        }
                    }.onMove { selection.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("开关控制列表显示内容，拖动右侧手柄或使用上下箭头调整顺序。偏好保存在本机当前登录身份下。")
                }
                Button("恢复默认字段") { selection = ListFieldSelection() }
                    .accessibilityIdentifier("list-fields.\(Field.storageNamespace).reset")
            }
            .scrollDismissesKeyboard(.interactively)
            .environment(\.editMode, .constant(.active))
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("list-fields.\(Field.storageNamespace).done")
                }
            }
        }
    }

    private func moveButton(_ field: Field, direction: Int) -> some View {
        let index = selection.orderedFields.firstIndex(of: field) ?? 0
        return Button {
            guard let current = selection.orderedFields.firstIndex(of: field) else { return }
            selection.move(fromOffsets: IndexSet(integer: current), toOffset: current + (direction < 0 ? -1 : 2))
        } label: {
            Image(systemName: direction < 0 ? "arrow.up" : "arrow.down")
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .disabled(direction < 0 ? index == 0 : index == selection.orderedFields.count - 1)
        .accessibilityLabel("\(direction < 0 ? "上移" : "下移")\(field.title)")
        .accessibilityIdentifier("list-fields.\(Field.storageNamespace).\(field.rawValue).\(direction < 0 ? "up" : "down")")
    }
}

/// A compact row that wraps each complete field into the next line. Measurements
/// are unconstrained so long field text grows vertically instead of truncating.
struct ListFieldFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 600, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                 proposal: ProposedViewSize(width: result.widths[index], height: nil))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint], widths: [CGFloat]) {
        let available = max(1, width)
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var positions: [CGPoint] = [], widths: [CGFloat] = []
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let measuredWidth = min(available, ideal.width)
            let size = subview.sizeThatFits(ProposedViewSize(width: measuredWidth, height: nil))
            if x > 0 && x + measuredWidth > available {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y)); widths.append(measuredWidth)
            x += measuredWidth + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: available, height: y + rowHeight), positions, widths)
    }
}
