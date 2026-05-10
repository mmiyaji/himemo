# HiMemo UI Behavior Guardrails

This document records UI behavior that has regressed more than once. Treat these as product requirements, not optional styling preferences.

## Media Previews

- Web, Android, iOS, and desktop should all show video thumbnails when a thumbnail can be generated or restored from sync data.
- Do not disable video thumbnail generation on Web. Web uses browser video/canvas APIs and should fall back to the video icon only when the selected file cannot be decoded.
- Videos must remain playable on Web. Web playback uses the browser native video element for blob URLs; do not replace it with a "preview unavailable" path or an icon-only fallback unless the media bytes are actually missing or undecodable.
- Sync/import flows must preserve or regenerate video preview metadata. A synced video should not become an icon-only attachment solely because it crossed devices or platforms.
- The note list thumbnail setting is intentionally binary: show media thumbnails, or show attachment-type icons. Do not reintroduce square-crop/contain mode choices unless there is a new product decision.

## Mobile Note Detail Sheet

- In phone-width layouts, opening a note detail is a full-screen modal sheet. The app header behind it does not need to remain visible and should not peek through.
- The sheet should cover the available viewport, including the area below the status bar, while respecting usable safe-area padding for controls.
- Dismissal should support the close button, route/tab changes, top-edge drag, and content-edge overscroll gestures.
- Drag-to-dismiss should follow common mobile behavior: while the drag is held, show stable feedback; close only when released beyond the threshold; if the user drags back under the threshold, keep the sheet open without flicker.
- Automated checks should cover these rules when the implementation changes. At minimum, keep tests that assert Web playback is enabled and that the full-screen mobile detail behavior is documented as a guarded product requirement.

## External Links

- Settings links that open external sites must show a confirmation dialog first.
- Author/profile links are external links and follow the same confirmation rule.

## Cloud Sync UX

- Manual Sync remains immediate when the transfer is reasonably small.
- If the estimated sync upload/download is at least 50 MB and the device is on a mobile data connection, show a confirmation dialog before starting the transfer.
- Automatic seamless sync must not start a large transfer on mobile data without user consent. Skip it silently and let the next manual Sync surface the confirmation.
- Large attachments may need a future lazy-download mode, but the current product behavior is full-bundle sync. Any lazy mode must preserve offline expectations and clearly mark attachments that are remote-only.
