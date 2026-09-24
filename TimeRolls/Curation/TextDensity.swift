//
//  TextDensity.swift
//  Time Rolls
//
//  How much of a photograph is words.
//
//  The old measure added up the bounding boxes of the individual lines of text and asked
//  whether they covered more than 18% of the frame. That is the right question asked in a
//  way that cannot answer it: a line of text is a thin sliver, and on a receipt almost all
//  of the paper lies in the gaps *between* the lines. Fifty lines of a supermarket receipt
//  sum to a fraction of the frame the receipt plainly occupies — and fast recognition on
//  crumpled paper at an angle in a car footwell loses half the lines before the sum even
//  starts. So a receipt reached a round asking which photograph was older.
//
//  Three readings instead of one, because a document gives itself away in three different
//  ways and a photograph with some writing in it gives itself away in none:
//
//  * **covered** — the old sum. Still right for a screenshot, where the text really does
//    tile the frame.
//  * **enclosed** — the single box containing every line. This is what catches paper: the
//    receipt's text runs in a tall narrow column, and the column is a third of the frame
//    even though the lines are slivers.
//  * **lines** — how many were found at all. Twenty-five lines is a wall of text whatever
//    shape it makes; nobody photographs their family and comes back with thirty lines.
//
//  Each threshold is paired with a line count, so a shopfront sign, a race number or a
//  birthday banner — few lines, large box — is still a photograph of an afternoon.
//

import Foundation
import CoreGraphics

nonisolated enum TextDensity {

    /// What the text in a photograph looks like, in the frame's own units (0…1).
    struct Reading: Equatable {
        /// How many separate pieces of text were found.
        var lines = 0
        /// The summed area of their boxes — the old measure.
        var covered = 0.0
        /// The area of one box containing all of them.
        var enclosed = 0.0
    }

    static func reading(from boxes: [CGRect]) -> Reading {
        guard !boxes.isEmpty else { return Reading() }
        var reading = Reading()
        reading.lines = boxes.count
        reading.covered = boxes.reduce(0.0) { $0 + Double($1.width * $1.height) }
        let hull = boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
        reading.enclosed = Double(hull.width * hull.height)
        return reading
    }

    /// Whether this is a photograph of words rather than of anything that happened.
    ///
    /// A face changes the answer. Somebody standing in front of a menu board, a noticeboard
    /// or a wall of writing is a photograph of *them*, and throwing it away because the
    /// wall behind them is covered in words would delete the kind of picture this game
    /// exists to show. So where a face was found, only the tiling test applies — the one
    /// a screenshot fails and a room with writing in it does not.
    static func looksLikeADocument(_ reading: Reading, hasFace: Bool = false) -> Bool {
        // A screenshot or a poster: the text really does tile the frame.
        //
        // With somebody in the picture the bar is nearly twice as high. A screenshot of a
        // conversation tiles 40% of the frame and more; a room with writing on the wall
        // rarely passes a quarter once a person is standing in front of it. Between those
        // two numbers sits every photograph of somebody at a noticeboard, a menu board or
        // a classroom wall, and those are memories.
        if reading.lines >= 4, reading.covered > (hasFace ? 0.35 : 0.18) { return true }
        guard !hasFace else { return false }
        // Paper: a column of writing over a fifth of the picture. Measured against the
        // receipt that got through, whose text encloses 23% while its lines sum to 8%.
        // The line count is what keeps a shop sign or a race number out of this.
        if reading.lines >= 8, reading.enclosed > 0.20 { return true }
        // A wall of text, whatever shape it makes.
        if reading.lines >= 25 { return true }
        return false
    }
}
