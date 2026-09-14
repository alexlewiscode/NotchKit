//
//  ClosedNotchRegion.swift
//  NotchAPI
//
//  The three horizontal regions of the closed notch.
//

import Foundation

/// A region of the closed notch that a contribution may target.
///
/// Contributions only compete inside their declared region. Phase 1 consumes the
/// `exclusion` region for the built-in closed content and reserves `leading` and
/// `trailing` for later migrations.
public enum ClosedNotchRegion: String, CaseIterable, Hashable {
    case leading
    case exclusion
    case trailing
}
