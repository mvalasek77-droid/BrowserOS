import Foundation

/// A ready-made showcase cut for the demo cutting room. Hand-built (not
/// derived from a plan) so it demonstrates every editing feature with data
/// that reads like a real production: named scenes, alternate takes, a
/// dissolve, dialogue and score.
///
/// The demo is in-memory only — nothing here is ever saved to the user's
/// project file. Exiting the demo restores their real sequence untouched.
enum DemoSequence {

    /// The clip colors the canvas paints for the demo, keyed by name prefix
    /// so the lanes look like a real edit.
    static let name = "Night Drive — Demo Cut"

    static func build() -> Timeline {
        var timeline = Timeline(name: name, fps: 24, resolution: Resolution(width: 1920, height: 1080))

        // MARK: V1 — picture

        let opening = Clip(
            name: "01 — City lights through rain",
            start: 0,
            duration: 6.5,
            sourceIn: 0,
            sourceOut: 6.5
        )
        place(opening, tool: "vid-kling", cost: 6.5 * 0.14, prompt: "noir city street at night, rain-slick asphalt, neon reflections, slow push-in", on: &timeline)

        var approach = Clip(
            name: "02 — The car approaches",
            start: 0,
            duration: 5.0,
            sourceIn: 0,
            sourceOut: 5.0
        )
        approach.transitionIn = Transition(type: "dissolve", duration: 0.5)
        place(approach, tool: "vid-ray", cost: 5.0 * 0.20, prompt: "black sedan glides through frame, headlights flare, handheld drift", on: &timeline)

        var dialogue = Clip(
            name: "03 — She waits at the diner",
            start: 0,
            duration: 8.0,
            sourceIn: 0,
            sourceOut: 8.0
        )
        place(dialogue, tool: "vid-gen", cost: 8.0 * 0.25, prompt: "1950s diner interior, woman alone in booth, red neon through blinds, static tripod", on: &timeline)

        var hero = Clip(
            name: "04 — Hero close-up, the line",
            start: 0,
            duration: 7.5,
            sourceIn: 0,
            sourceOut: 7.5
        )
        place(hero, tool: "vid-flagship", cost: 7.5 * 0.50, prompt: "extreme close-up, eyes catch the neon, one line of dialogue, anamorphic flare", on: &timeline)

        var getaway = Clip(
            name: "05 — The getaway",
            start: 0,
            duration: 6.0,
            sourceIn: 0,
            sourceOut: 6.0
        )
        getaway.transitionIn = Transition(type: "dissolve", duration: 0.75)
        place(getaway, tool: "vid-kling", cost: 6.0 * 0.14, prompt: "car peels out, tire spray, low-angle hero shot, motion blur", on: &timeline)

        var dawn = Clip(
            name: "06 — Dawn over the bridge",
            start: 0,
            duration: 7.0,
            sourceIn: 0,
            sourceOut: 7.0
        )
        place(dawn, tool: "vid-ray", cost: 7.0 *  0.20, prompt: "golden-hour skyline, bridge cables silhouetted, slow aerial drift", on: &timeline)

        // MARK: A1 — dialogue (synced to the clips that need it)

        for (name, duration, at) in [
            ("03 DX — \"You're late.\"", 8.0, 19.0),   // dialogue scene
            ("04 DX — \"I had to be sure.\"", 7.5, 27.0), // hero line
        ] {
            var dx = Clip(name: name, start: at, duration: duration, sourceIn: 0, sourceOut: duration)
            dx.provenance = Provenance(toolID: "voice-pro", cost: (duration / 60) * 0.30, prompt: "noir delivery, world-weary")
            _ = try? timeline.append(dx, to: "A1")
        }

        // MARK: A2 — score

        var score = Clip(name: "Score — brass & rain", start: 0, duration: 33.0, sourceIn: 0, sourceOut: 33.0)
        score.provenance = Provenance(toolID: "music-pro", cost: (33.0 / 60) * 0.60, prompt: "slow jazz-noir score, muted trumpet, rain texture")
        _ = try? timeline.append(score, to: "A2")

        // MARK: Markers

        timeline.addMarker(at: 0, name: "Cold open")
        timeline.addMarker(at: 19.0, name: "Scene 2 — diner")
        timeline.addMarker(at: 40.0, name: "Tag")

        // Alternate take on the hero shot so take-swapping shows money moving.
        if let heroClip = timeline.clip(hero.id) {
            try? timeline.addTake(
                Take(toolID: "vid-gen", cost: 7.5 * 0.25, prompt: "same line, wider framing, rain in foreground"),
                to: heroClip.id,
                select: false
            )
        }

        return timeline
    }

    /// Place a video clip on V1 with provenance + a selected take, so the
    /// inspector shows real cost data from the first tap.
    private static func place(_ clip: Clip, tool: String, cost: Double, prompt: String,
                               on timeline: inout Timeline) {
        var placed = clip
        placed.provenance = Provenance(toolID: tool, cost: cost, prompt: prompt)
        if let appended = try? timeline.append(placed, to: "V1") {
            _ = try? timeline.addTake(Take(toolID: tool, cost: cost, prompt: prompt), to: appended.id)
        }
    }
}