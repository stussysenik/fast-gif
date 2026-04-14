import SwiftUI

/// Origami spring language — the FastGIF house motion vocabulary.
///
/// Tuned after Facebook Origami's tension/friction parameterization, mapped to
/// SwiftUI's `response`/`dampingFraction` model. Every animation in FastGIF
/// should use one of these four springs; ad-hoc `.spring()` literals are not
/// allowed. This is the backing vocabulary referenced by the v1.0 plan §3.
///
/// - `.origamiFlick`: fast settle (drag-end, scrub release). Tension 80, friction 10.
/// - `.origamiTap`: the house spring (grab, hover lift, generic state change).
/// - `.origamiMorph`: slower morph (sheets, expansions, hero transitions).
/// - `.origamiSettle`: gentle residual decay for velocity continuity landings.
enum Motion {
    /// Fast, crisp settle for drag-end and scrub release events.
    /// Origami (tension 80, friction 10) ≈ SwiftUI response 0.30 damping 0.80.
    static let flick = Animation.spring(response: 0.30, dampingFraction: 0.80)

    /// The default house spring. Grab lift, tap feedback, state changes.
    /// Origami (tension 40, friction 7) ≈ SwiftUI response 0.45 damping 0.72.
    static let tap = Animation.spring(response: 0.45, dampingFraction: 0.72)

    /// Slower morph for sheets, expansions, and hero transitions.
    static let morph = Animation.spring(response: 0.55, dampingFraction: 0.82)

    /// Gentle residual decay for velocity-continuity landings.
    static let settle = Animation.spring(response: 0.65, dampingFraction: 0.88)
}
