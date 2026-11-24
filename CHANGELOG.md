# Changelog

## 1.0.0

- First release: now playing from every MPRIS source, with a chip per source, cover-colored card, seek, transport, volume, hover preview, keyboard control and IPC.
- **Video view:** a live, zoomable view of the playing window in the card, with Picture-in-Picture detection and "Bring it forward" for background tabs.
- The cover keeps its size when paused; it dims instead of shrinking.
- **Edge cases:** site names and glyphs for 30+ platforms; the site comes from Brave/Chrome window titles; no "any window" guessing for Video; a source must play 2 s before taking the bar; the selection is frozen while the card is open; playing sources with no title are kept.
- **Design pass** (reviewed by a design expert and a UI/UX expert):
  - Logos never become the cover: a title card is shown instead.
  - Chips are labelled by site; the current source comes first, sources paused for over 30 min fade, and chips are at least 28 px tall.
  - Titles wrap to two lines; a LIVE pill replaces the seek bar on live streams; unsupported shuffle/repeat are hidden.
  - The footer shows the state ("Paused · 2 h ago"), with `?` opening the shortcuts sheet.
  - Fewer looping animations; a neutral count bubble and a smaller badge in the bar.
