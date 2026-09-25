//
//  NetworkReach.swift
//  Time Rolls
//
//  What kind of connection this is, so the game can decide what it may fetch.
//
//  Only one question is asked here: is the link one somebody pays for by the megabyte.
//  Nothing else about the network is any of the game's business.
//

import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkReach {

    static let shared = NetworkReach()

    /// Whether this connection costs money to use — cellular, or a personal hotspot.
    ///
    /// `isExpensive` covers both, and covers them better than asking for the interface
    /// type: a phone sharing its connection over Wi-Fi is Wi-Fi by interface and mobile
    /// data in every way that matters to the person paying for it.
    private(set) var isExpensive = false

    /// Whether the link is one iOS has been told to go easy on — Low Data Mode.
    private(set) var isConstrained = false

    /// Set once the monitor has actually reported. Before that nothing is assumed: the
    /// game starts optimistic rather than refusing to fetch on a connection it has not
    /// looked at yet.
    private(set) var hasReported = false

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained
                self.hasReported = true
            }
        }
        monitor.start(queue: DispatchQueue(label: "co.attimis.timerolls.reach"))
    }
}
