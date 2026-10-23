import SwiftUI

struct SwitcherView: View {
    let model: SwitcherModel

    var body: some View {
        let layout = model.layout
        // Tiles are placed by `SwitcherLayout.tileFrame` and keyed by window, so
        // when one is closed it fades out and the others slide into place.
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                if let frame = layout.tileFrame(at: index) {
                    TileView(
                        window: window,
                        image: model.thumbnails[window.id],
                        thumbSize: layout.thumbSize,
                        titleHeight: layout.titleHeight,
                        iconsOnly: layout.iconsOnly,
                        selected: index == model.selected,
                        button: model.hovered == index
                            ? TileButton(hot: model.buttonHot, quit: model.quitMode) : nil
                    )
                    .equatable()
                    .position(x: frame.midX, y: frame.midY)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height, alignment: .topLeading)
    }
}

struct TileView: View, Equatable {
    let window: WindowInfo
    let image: CGImage?
    let thumbSize: CGSize
    let titleHeight: CGFloat
    let iconsOnly: Bool
    let selected: Bool
    /// The close / quit button, shown while the pointer is over this tile.
    let button: TileButton?

    static func == (a: TileView, b: TileView) -> Bool {
        a.window == b.window && a.image === b.image && a.thumbSize == b.thumbSize
            && a.titleHeight == b.titleHeight && a.iconsOnly == b.iconsOnly && a.selected == b.selected
            && a.button == b.button
    }

    private var iconSize: CGFloat { max(22, min(32, thumbSize.width * 0.14)) }

    var body: some View {
        VStack(spacing: 0) {
            thumbnail
                .frame(width: thumbSize.width, height: thumbSize.height)
                .overlay(alignment: .bottomLeading) {
                    if !iconsOnly, image != nil, let icon = window.icon {
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
                    .foregroundStyle(.primary.opacity(selected ? 1 : 0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: thumbSize.width, height: titleHeight, alignment: .bottom)
            }
        }
        .padding(SwitcherLayout.tileInset)
        // Filled highlight plus a thick blue border (thin strokes smear on non-Retina).
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.primary.opacity(selected ? 0.11 : 0))
        }
        .overlay {
            // Blue border on the selected tile, alongside the grey fill.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Brand.blue, lineWidth: 2.5)
                .opacity(selected ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: selected)
        }
        .overlay(alignment: .topTrailing) {
            if let button {
                button.padding(SwitcherLayout.buttonInset)
            }
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if iconsOnly {
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: thumbSize.height, height: thumbSize.height)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }
        } else if let image {
            Image(decorative: image, scale: 2)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        } else {
            // Placeholder until the first capture lands (usually a few ms).
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.primary.opacity(0.06))
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

/// Round button in a hovered tile's corner: ✕ closes the window, or with the quit
/// modifier held, ⏻ quits the app. Its position matches `SwitcherLayout.buttonFrame`.
struct TileButton: View, Equatable {
    let hot: Bool
    let quit: Bool

    var body: some View {
        Image(systemName: quit ? "power" : "xmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: SwitcherLayout.buttonSize, height: SwitcherLayout.buttonSize)
            // White in both themes so it reads on any thumbnail; under the pointer
            // it grows slightly and lifts.
            .background { Circle().fill(.white) }
            .overlay { Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
            .shadow(color: .black.opacity(hot ? 0.4 : 0.25), radius: hot ? 3 : 2, y: 1)
            .scaleEffect(hot ? 1.1 : 1)
            .help(quit ? "Quit App" : "Close Window")
    }
}
