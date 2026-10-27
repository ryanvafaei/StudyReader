# Backlog (Phase 1 end-of-phase fix pass)

Rule (user, 2026-10-27): no polish tasks mid-phase. Anything that is not a spec FAIL at a checkpoint (UX items, visual nits, open observations) goes here and gets one fix pass at the end of Phase 1, planned by architect. Only spec FAILs become fix tasks right away.

| ID | Source | Item | Notes |
|---|---|---|---|
| O1 | T52 cloud checkpoint | After Move Tab to New Window and Merge All Windows the reader tab comes first and the Library tab second. | Open until the user checks the real tab drag on a Mac. |
| B1 | T52j review | After a quiet import (no alert) there is no visible confirmation when no library window is visible (Open With while the library window is closed or minimised). | A small non-modal indicator would be a later change. User has not asked for it. |
| B2 | T52b review | Zoom (green button, titlebar double-click) while a reader tab is open may be reverted when the last reader tab closes; full screen untested. | Mac check first. |
| B3 | T52h review | `ReaderTabbingTests/joinChangesNoFrameSynchronously` only covers the property side (the test window has no anchor). | Add an anchored variant if feasible. |
| B4 | T52j review | The "no alert" assertions in `ExternalOpenTests` run right after the card appears; a late alert could slip past. | Add a short wait or settle. |
| B5 | T53 review | If the initial PDF position restore hits its 2 s retry limit without a window, tracking still starts and a later layout could report page 0 over the saved position. | Very unlikely; skip `beginTrackingPosition` on timeout until the view has a window. |
| B6 | T55 review | `TextReaderView.onClick` fires after a link click too (super already opened the link) and its Bool return is ignored. | T60 decides whether a click on a link inside a highlight is handled; honour the return or document the order. |
| B7 | T55 review | `TextReaderController.firstVisibleOffset()` returns 0 when no fragment is found; during tracking before layout it could report 0. | Return the last known offset or skip reporting. |
| B8 | T55 review | The default context menu's "Open Link" item may bypass the http/https/mailto filter; `@preconcurrency` on the layout-manager delegate lacks a one-line justification comment. | Check on a Mac; override `menu(for:)`/`openLink` if it bypasses. |
| B9 | T56 review | No test covers a rotated page or a crop box with a non-zero origin for PDF anchors. | Add a fixture in a later fix pass. |
