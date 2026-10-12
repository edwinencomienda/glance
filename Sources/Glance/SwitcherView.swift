import SwiftUI

struct SwitcherView: View {
    let model: SwitcherModel

    var body: some View {
        let layout = model.layout
        VStack(spacing: SwitcherLayout.spacing) {
            ForEach(0..<layout.rows, id: \.self) { row in
                HStack(spacing: SwitcherLayout.spacing) {
                    ForEach(0..<layout.itemsInRow(row), id: \.self) { col in
                        let index = row * layout.columns + col
                        if index < model.windows.count {
                            let window = model.windows[index]
                            TileView(
                                window: window,
                                image: model.thumbnails[window.id],
                                thumbSize: layout.thumbSize,
                                titleHeight: layout.titleHeight,
                                selected: index == model.selected
                            )
                            .equatable()
                        }
                    }
                }
            }
        }
        .padding(SwitcherLayout.padding)
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
    }
}

struct TileView: View, Equatable {
    let window: WindowInfo
    let image: CGImage?
    let thumbSize: CGSize
    let titleHeight: CGFloat
    let selected: Bool

    static func == (a: TileView, b: TileView) -> Bool {
        a.window == b.window && a.image === b.image && a.thumbSize == b.thumbSize
            && a.titleHeight == b.titleHeight && a.selected == b.selected
    }

    private var iconSize: CGFloat { max(22, min(32, thumbSize.width * 0.14)) }

    var body: some View {
        VStack(spacing: 0) {
            thumbnail
                .frame(width: thumbSize.width, height: thumbSize.height)
                .overlay(alignment: .bottomLeading) {
                    if image != nil, let icon = window.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: iconSize, height: iconSize)
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                            .offset(x: -4, y: 6)
                    }
                }

            if titleHeight > 0 {
                Text(window.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(selected ? 0.95 : 0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: thumbSize.width, height: titleHeight, alignment: .bottom)
            }
        }
        .padding(SwitcherLayout.tileInset)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(selected ? 0.14 : 0))
                .strokeBorder(.white.opacity(selected ? 0.18 : 0), lineWidth: 1)
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let image {
            Image(decorative: image, scale: 2)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        } else {
            // Placeholder until the first capture lands (usually a few ms).
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay {
                    if let icon = window.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: thumbSize.height * 0.42, height: thumbSize.height * 0.42)
                    }
                }
        }
    }
}
