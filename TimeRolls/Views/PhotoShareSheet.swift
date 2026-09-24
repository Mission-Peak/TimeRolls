//
//  PhotoShareSheet.swift
//  Time Rolls
//
//  Sending a photograph to somebody, from the screen where it is still in front of them.
//
//  The game brings up pictures people had forgotten they owned, and the natural next
//  thought is "I should send this to her". Answering that with "open Photos and find it
//  again" loses it: a photograph somebody saw thirty seconds ago is not a photograph they
//  can search for, and by the time it has been found the thought has gone.
//
//  Nothing is sent by the app. Tapping a photograph opens iOS's own share sheet, where the
//  person chooses who gets it and whether to send it at all — which is the only way an app
//  for somebody with memory difficulties should ever be allowed near "send".
//

import SwiftUI

struct PhotoShareSheet: View {

    let photos: [GamePhoto]
    let provider: ImageProvider

    @Environment(\.dismiss) private var dismiss
    @Environment(\.photoTextScale) private var textScale

    /// Full-size copies, written out only when one is chosen.
    @State private var sharing: SharableImage?
    @State private var preparing: String?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Tap a photo to send it.")
                    .font(.system(size: 17 * textScale, design: .rounded))
                    .foregroundStyle(Meadow.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(photos) { photo in
                        Button {
                            Task { await prepare(photo) }
                        } label: {
                            SharablePhotoTile(photo: photo,
                                              provider: provider,
                                              isPreparing: preparing == photo.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Send this photo")
                    }
                }
                .padding(18)
            }
            .background(Meadow.cardCream.opacity(0.4))
            .navigationTitle("Today's photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
            }
        }
        .sheet(item: $sharing) { item in
            ShareSheet(items: [item.url])
        }
    }

    /// Write the photograph to a file and hand it to iOS.
    ///
    /// A file rather than a `UIImage`, because sharing an image in memory gives whoever
    /// receives it a re-encoded copy at whatever size the screen happened to need. Somebody
    /// sending a photograph of their wedding to their daughter should be sending the
    /// photograph, not a thumbnail of it.
    private func prepare(_ photo: GamePhoto) async {
        preparing = photo.id
        defer { preparing = nil }
        guard let image = await provider.image(for: photo,
                                               targetSize: CGSize(width: 3000, height: 3000)),
              let data = image.jpegData(compressionQuality: 0.95) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeRolls-\(UUID().uuidString).jpg")
        guard (try? data.write(to: url)) != nil else { return }
        sharing = SharableImage(url: url)
    }
}

private struct SharableImage: Identifiable {
    let url: URL
    var id: String { url.lastPathComponent }
}

private struct SharablePhotoTile: View {
    let photo: GamePhoto
    let provider: ImageProvider
    let isPreparing: Bool

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .alignmentGuideForSubject(photo.subjectArea)
            } else {
                Meadow.cardSky
            }
            if isPreparing {
                Color.black.opacity(0.35)
                ProgressView().tint(.white)
            }
        }
        .frame(height: 104)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white, lineWidth: 3)
        }
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .task(id: photo.id) {
            image = await provider.image(for: photo,
                                         targetSize: CGSize(width: 400, height: 400))
        }
    }
}

/// iOS's own share sheet. Nothing is chosen here and nothing is sent by the app.
/// iOS's own share sheet. Used by the end-of-session sharing here, and by the zoomed
/// photograph, which is the other place somebody thinks "I should send this".
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
