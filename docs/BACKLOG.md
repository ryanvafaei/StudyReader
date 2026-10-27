# Backlog (Phase 1 end-of-phase fix pass)

Rule (user, 2026-10-27): no polish tasks mid-phase. Anything that is not a spec FAIL at a checkpoint (UX items, visual nits, open observations) goes here and gets one fix pass at the end of Phase 1, planned by architect. Only spec FAILs become fix tasks right away.

| ID | Source | Item | Notes |
|---|---|---|---|
| O1 | T52 cloud checkpoint | After Move Tab to New Window and Merge All Windows the reader tab comes first and the Library tab second. | Open until the user checks the real tab drag on a Mac. |
| B1 | T52j review | After a quiet import (no alert) there is no visible confirmation when no library window is visible (Open With while the library window is closed or minimised). | A small non-modal indicator would be a later change. User has not asked for it. |
| B2 | T52b review | Zoom (green button, titlebar double-click) while a reader tab is open may be reverted when the last reader tab closes; full screen untested. | Mac check first. |
| B3 | T52h review | `ReaderTabbingTests/joinChangesNoFrameSynchronously` only covers the property side (the test window has no anchor). | Add an anchored variant if feasible. |
| B4 | T52j review | The "no alert" assertions in `ExternalOpenTests` run right after the card appears; a late alert could slip past. | Add a short wait or settle. |
