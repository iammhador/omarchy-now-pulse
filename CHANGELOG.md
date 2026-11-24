# Changelog

## 1.1.0

- **Pop-up on track change:** a small card under the bar with the cover, title, artist and source. Quiet during Do Not Disturb, over fullscreen windows and while you're looking at the playing app. Settings `trackToast` and `toastSeconds`; IPC `toast`.
- **Video changes no longer blank the bar:** a source between two tracks (YouTube autoplay, clicking another video) is held for up to 12 s instead of disappearing, so the card stays open too.
- **Site names stick:** in Brave and Chrome the site is remembered while its tab is in the background; sites named only by their title ("Instagram", "KICK") and "… on TikTok" are recognized; unknown sites are named from the window title ("Framatube", "NASA+").
- **Proper site names** for 50 more sites (9GAG, NASA, SomaFM, TuneIn, Internet Archive, TED, NPR, BBC, Bilibili, Niconico, Al Jazeera, Toffee, Binge, Somoy TV and more), and the subdomain for github.io / Vercel / Netlify / appspot hosted sites.
- **No false LIVE:** Zen and Firefox send no track length, so every video showed LIVE; now LIVE only shows for streams that look live.
- Fixed `null` errors in the log while playback stopped.
- `tools/fake-player.py` and IPC `demo` for testing and screenshots without real media.
- Tested against 56 sites in Chromium and Zen.

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
