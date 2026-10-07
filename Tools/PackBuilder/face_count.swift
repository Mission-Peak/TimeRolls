// Counts the faces in each photograph, with Apple's own detector — the same one the app
// runs on the player's photographs, so a pack is held to the rule the game plays by.
//
//   swift Tools/PackBuilder/face_count.swift a.jpg b.jpg …
//
// Prints one JSON object: path → {"faces": n, "largest": share of the frame the biggest
// face fills}. A file that cannot be read is left out rather than reported as faceless:
// "nobody looked" is not "nobody there".

import Foundation
import Vision

var out: [String: [String: Double]] = [:]
for path in CommandLine.arguments.dropFirst() {
    let request = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(url: URL(fileURLWithPath: path))
    do {
        try handler.perform([request])
    } catch {
        continue
    }
    let faces = request.results ?? []
    let largest = faces.map { $0.boundingBox.width * $0.boundingBox.height }.max() ?? 0
    out[path] = ["faces": Double(faces.count), "largest": Double(largest)]
}
let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
