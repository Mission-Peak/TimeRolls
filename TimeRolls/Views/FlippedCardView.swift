//
//  FlippedCardView.swift
//  Time Rolls
//
//  The back of a photo card, read full screen.
//
//  It used to turn over in place, in the grid. Two things were wrong with that on a phone.
//  The card had to grow to make the writing legible, and growing meant overlapping the
//  photograph above it — so reading one card hid another. And any number could be turned
//  at once, which left a round looking like a pile of text with the pictures somewhere
//  underneath.
//
//  Full screen solves both without a compromise: the writing is as large as it needs to
//  be, nothing is covered by accident, and only one card can be open because only one
//  screen exists.
//

import SwiftUI

struct FlippedCardView: View {

    let photo: GamePhoto
    let provider: ImageProvider
    let onClose: () -> Void

    @Environment(\.photoHighContrast) private var highContrast
    @Environment(\.photoTextScale) private var textScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 16) {
                // A small picture above the words, so it is still clear which card this
                // is. Reading is the point here, not looking — the zoom is for looking.
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let fact = photo.fact {
                            FactText(fact: fact, name: photo.title,
                                     size: 20 * textScale,
                                     bodyColour: highContrast ? Palette.ink(true) : Meadow.body)
                        } else if let title = photo.title {
                            Text(title)
                                .font(.system(size: 24 * textScale, weight: .heavy,
                                              design: .rounded))
                                .foregroundStyle(Meadow.title)
                        } else {
                            Text("Nothing is known about this one.")
                                .font(.system(size: 18 * textScale, design: .rounded))
                                .foregroundStyle(Meadow.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .background(highContrast ? AnyShapeStyle(Palette.surface(true))
                                         : AnyShapeStyle(Meadow.cardCream),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                Button(action: onClose) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 19, weight: .black))
                        Text("Back to the photos")
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(Meadow.woodInk)
                    .padding(.horizontal, 22)
                    .frame(height: 54)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .readableColumn(maxWidth: 620)
        }
        .task(id: photo.id) {
            image = await provider.image(for: photo,
                                         targetSize: CGSize(width: 700, height: 700))
        }
    }
}
