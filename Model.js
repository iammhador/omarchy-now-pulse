.pragma library

// Now Pulse: pure logic, no QML types. Players are read through plain
// properties (dbusName, identity, desktopEntry, isPlaying, trackTitle, ...)
// so the node tests can pass simple objects.

// ---------------------------------------------------------------- players

// playerctld re-exports whichever player was active last, so it would show
// every source twice.
function isProxy(player) {
  return /^org\.mpris\.MediaPlayer2\.playerctld(?:$|\.)/i.test(String(player && player.dbusName || ""))
}

function isSpotify(player) {
  return !!player && /^org\.mpris\.MediaPlayer2\.spotify(?:[._-]|$)/i.test(String(player.dbusName || ""))
}

function key(player) {
  return player ? String(player.dbusName || player.identity || "") : ""
}

// The players worth showing: real sources that have something loaded.
function filterPlayers(players, opts) {
  var out = []
  var skipSpotify = !!(opts && opts.skipSpotify)
  for (var i = 0; i < (players ? players.length : 0); i++) {
    var p = players[i]
    if (!p || isProxy(p)) continue
    if (skipSpotify && isSpotify(p)) continue
    if (String(p.trackTitle || "").trim() === "" && !p.isPlaying) continue
    out.push(p)
  }
  return out
}

// Which player the bar shows:
//   1. the one you picked in the card, while it's still around;
//   2. the playing one that started most recently;
//   3. the paused one that played most recently;
//   4. the first one.
// `lastPlayed` maps key -> time it last started playing.
function selectActive(players, pinned, lastPlayed) {
  if (!players || players.length === 0) return null
  var when = lastPlayed || {}
  if (pinned) {
    for (var i = 0; i < players.length; i++) if (key(players[i]) === pinned) return players[i]
  }
  var best = null, bestT = -1, bestPlaying = false
  for (var j = 0; j < players.length; j++) {
    var p = players[j]
    var t = Number(when[key(p)]) || 0
    var playing = !!p.isPlaying
    if (playing && !bestPlaying) { best = p; bestT = t; bestPlaying = true; continue }
    if (playing !== bestPlaying) continue
    if (t > bestT) { best = p; bestT = t }
  }
  return best || players[0]
}

// The key after (dir 1) or before (dir -1) `current`, wrapping around.
function cycleKey(players, current, dir) {
  if (!players || players.length === 0) return ""
  var idx = -1
  for (var i = 0; i < players.length; i++) if (key(players[i]) === current) idx = i
  var n = players.length
  var next = idx < 0 ? 0 : ((idx + (dir < 0 ? -1 : 1)) % n + n) % n
  return key(players[next])
}

// ---------------------------------------------------------------- apps

// Known apps: [pattern over "desktopEntry identity dbusName", name, glyph].
var APPS = [
  [/spotify/i, "Spotify", "󰓇"],
  [/brave/i, "Brave", "󰖟"],
  [/\bzen\b|zen[-_.]browser/i, "Zen", "󰈹"],
  [/librewolf/i, "LibreWolf", "󰈹"],
  [/firefox/i, "Firefox", "󰈹"],
  [/chromium/i, "Chromium", "󰊯"],
  [/chrome/i, "Chrome", "󰊯"],
  [/vivaldi/i, "Vivaldi", "󰖟"],
  [/\bedge\b|msedge/i, "Edge", "󰇩"],
  [/\bmpv\b/i, "mpv", "󰐌"],
  [/vlc/i, "VLC", "󰕼"],
  [/youtube[-_ ]?music|pear-desktop|th-ch/i, "YouTube Music", "󰗃"],
  [/tidal/i, "TIDAL", "󰝚"],
  [/rhythmbox/i, "Rhythmbox", "󰝚"],
  [/elisa/i, "Elisa", "󰝚"],
  [/amberol/i, "Amberol", "󰝚"],
  [/cmus/i, "cmus", "󰝚"],
  [/mpd/i, "MPD", "󰝚"],
  [/kdeconnect/i, "Phone", "󰄜"]
]

function _haystack(player) {
  return [player.desktopEntry, player.identity, player.dbusName].map(function(v) { return String(v || "") }).join(" ")
}

function _known(player) {
  var h = _haystack(player || {})
  for (var i = 0; i < APPS.length; i++) if (APPS[i][0].test(h)) return APPS[i]
  return null
}

// "Brave", "Zen", "mpv"... from the MPRIS identity when the app is unknown.
function appName(player) {
  if (!player) return ""
  var k = _known(player)
  if (k) return k[1]
  var id = String(player.identity || "").replace(/^mozilla\s+/i, "").trim()
  if (id === "") id = String(player.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, "").split(".")[0]
  return id ? id.charAt(0).toUpperCase() + id.slice(1) : "Player"
}

function appGlyph(player) {
  var k = _known(player)
  return k ? k[2] : "󰝚"
}

// Name to look the app's .desktop entry up by (for its real icon).
function desktopId(player) {
  if (!player) return ""
  if (player.desktopEntry) return String(player.desktopEntry)
  var bus = String(player.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, "").split(".")[0]
  return bus === "brave" ? "brave-browser" : bus
}

// Hyprland window class pattern for focusing the app.
function windowClass(player) {
  var id = desktopId(player).replace(/[^A-Za-z0-9_.-]/g, "")
  return id ? "class:^(" + id + ")$" : ""
}

// The window showing this player's video, as an index into `windows`
// ([{appId, title}]), or -1 when it can't be told for sure. A
// Picture-in-Picture window is the video itself, so it wins; otherwise the
// window whose title (the active tab) holds the track title. Never "any
// window of the app": with one player per browser process, that would
// mirror an unrelated page. Generic titles ("Instagram") can't match.
function pickWindow(windows, appId, trackTitle) {
  var want = String(appId || "").toLowerCase()
  if (!windows || want === "") return -1
  var generic = isGenericTitle(trackTitle, "")
  var t = String(trackTitle || "").toLowerCase().trim().slice(0, 40)
  var titled = -1
  for (var i = 0; i < windows.length; i++) {
    var w = windows[i]
    if (!w || String(w.appId || "").toLowerCase() !== want) continue
    var title = String(w.title || "").toLowerCase()
    if (/picture[- ]in[- ]picture/.test(title)) return i
    if (titled < 0 && !generic && title.indexOf(t) !== -1) titled = i
  }
  return titled
}

// Whether a window title (the browser's active tab) is this track: if not,
// the video plays in a background tab and a mirror would show another page.
function showsTrack(windowTitle, trackTitle) {
  var t = String(trackTitle || "").toLowerCase().trim().slice(0, 40)
  var w = String(windowTitle || "").toLowerCase()
  return t === "" || /picture[- ]in[- ]picture/.test(w) || w.indexOf(t) !== -1
}

// Zoom / pan for the video view. `v` = {zoom, x, y} with x, y the content
// offset in px (<= 0). Keeps the content covering the viewport (or centered
// when smaller). bw/bh: content size at zoom 1; vw/vh: viewport size.
function clampView(v, bw, bh, vw, vh) {
  var z = clamp(Number(v.zoom) || 1, 1, 8)
  var cw = bw * z, ch = bh * z
  var x = cw <= vw ? (vw - cw) / 2 : clamp(Number(v.x) || 0, vw - cw, 0)
  var y = ch <= vh ? (vh - ch) / 2 : clamp(Number(v.y) || 0, vh - ch, 0)
  return { zoom: z, x: x, y: y }
}

// Zoom by `factor` keeping the point (px, py) of the viewport still.
function zoomAt(v, factor, px, py, bw, bh, vw, vh) {
  var z0 = Number(v.zoom) || 1
  var z1 = clamp(z0 * factor, 1, 8)
  var k = z1 / z0
  return clampView({ zoom: z1, x: px - (px - v.x) * k, y: py - (py - v.y) * k }, bw, bh, vw, vh)
}

// Known sites: host -> [name, glyph]. Matched on the host or any parent
// domain, and on the name at the end of a window title.
var SITES = {
  "music.youtube.com": ["YouTube Music", "󰗃"], "youtube.com": ["YouTube", "󰗃"], "youtu.be": ["YouTube", "󰗃"],
  "instagram.com": ["Instagram", "󰋾"], "tiktok.com": ["TikTok", "󰝚"], "facebook.com": ["Facebook", "󰈌"],
  "fb.watch": ["Facebook", "󰈌"], "reddit.com": ["Reddit", "󰑍"], "redd.it": ["Reddit", "󰑍"],
  "x.com": ["X", "󰕄"], "twitter.com": ["X", "󰕄"], "snapchat.com": ["Snapchat", "󰒶"],
  "web.whatsapp.com": ["WhatsApp", "󰖣"], "whatsapp.com": ["WhatsApp", "󰖣"],
  "dailymotion.com": ["Dailymotion", "󰕧"], "vimeo.com": ["Vimeo", "󰕷"], "twitch.tv": ["Twitch", "󰕃"],
  "kick.com": ["Kick", "󰕧"], "netflix.com": ["Netflix", "󰝆"], "primevideo.com": ["Prime Video", "󰕧"],
  "disneyplus.com": ["Disney+", "󰕧"], "hotstar.com": ["Hotstar", "󰕧"], "chorki.com": ["Chorki", "󰕧"],
  "hoichoi.tv": ["Hoichoi", "󰕧"], "bongobd.com": ["Bongo", "󰕧"], "linkedin.com": ["LinkedIn", "󰌻"],
  "pinterest.com": ["Pinterest", "󰐃"], "discord.com": ["Discord", "󰙯"], "udemy.com": ["Udemy", "󰑴"],
  "coursera.org": ["Coursera", "󰑴"], "open.spotify.com": ["Spotify", "󰓇"], "soundcloud.com": ["SoundCloud", "󰓀"],
  "bandcamp.com": ["Bandcamp", "󰝚"], "music.apple.com": ["Apple Music", "󰝚"], "deezer.com": ["Deezer", "󰝚"],
  "tidal.com": ["TIDAL", "󰝚"]
}

function _siteEntry(host) {
  if (SITES[host]) return SITES[host]
  for (var h in SITES) if (host.slice(-(h.length + 1)) === "." + h) return SITES[h]
  return null
}

// Which site a URL is from: "YouTube", or the host's main label
// capitalized ("poridhi.io" -> "Poridhi"). "" for non-web URLs.
function siteName(url) {
  var m = /^https?:\/\/([^\/?#:]+)/i.exec(String(url || ""))
  if (!m) return ""
  var host = m[1].toLowerCase().replace(/^(www|m|web|mobile)\./, "")
  var e = _siteEntry(host) || _siteEntry("web." + host)
  if (e) return e[0]
  var parts = host.split(".")
  var label = parts.length > 1 ? parts[parts.length - 2] : parts[0]
  if (label.length <= 3 && parts.length > 2) label = parts[parts.length - 3]   // bbc.co.uk
  if (label.length <= 3) return label.toUpperCase()                         // bbc -> BBC
  return label ? label.charAt(0).toUpperCase() + label.slice(1) : ""
}

function siteGlyph(name) {
  var n = String(name || "").toLowerCase()
  for (var h in SITES) if (SITES[h][0].toLowerCase() === n) return SITES[h][1]
  return ""
}

// Browsers end window titles with their own name; strip it.
function _stripBrowser(title) {
  return String(title || "")
    .replace(/\s+[-—–]\s+(brave|chromium|google chrome|vivaldi|microsoft edge|zen browser|mozilla firefox|librewolf|firefox)$/i, "")
    .replace(/^\(\d+\+?\)\s+/, "")   // "(209) " notification counts
}

// The site a window title names at its end ("Song - YouTube - Brave" ->
// "YouTube"), when it's one we know. Brave and Chrome give MPRIS no URL.
function siteFromTitle(title) {
  var t = _stripBrowser(title)
  var m = /(?:\s[-—–|•·]\s|^)([^-—–|•·]+)$/.exec(t)
  var last = m ? m[1].trim().toLowerCase() : ""
  if (last === "") return ""
  for (var h in SITES) if (SITES[h][0].toLowerCase() === last) return SITES[h][0]
  return ""
}

// A title that says nothing about the content ("Instagram", "Facebook",
// "Video"): can't be used to find the right window.
function isGenericTitle(title, site) {
  var t = String(title || "").trim().toLowerCase()
  if (t.length < 4) return true
  if (site && t === String(site).toLowerCase()) return true
  for (var h in SITES) if (SITES[h][0].toLowerCase() === t) return true
  return /^(video|audio|media|untitled|playing)$/.test(t)
}

// Apps that play sound without a video worth mirroring.
function isAudioApp(player) {
  return isSpotify(player) || /tidal|rhythmbox|elisa|amberol|cmus|mpd|youtube[-_ ]?music|pear-desktop/i.test(_haystack(player || {}))
}

function isBrowser(player) {
  return /brave|zen|firefox|librewolf|chrom|vivaldi|edge|opera/i.test(_haystack(player || {}))
}

// "now", "4 m", "2 h", "3 d" ago.
function ago(ms) {
  var s = Math.max(0, Math.floor(Number(ms) / 1000) || 0)
  if (s < 60) return "just now"
  if (s < 3600) return Math.floor(s / 60) + " m ago"
  if (s < 86400) return Math.floor(s / 3600) + " h ago"
  return Math.floor(s / 86400) + " d ago"
}

// ---------------------------------------------------------------- text

function timestamp(seconds) {
  var value = Number(seconds)
  var total = isFinite(value) ? Math.max(0, Math.floor(value)) : 0
  var h = Math.floor(total / 3600), m = Math.floor(total % 3600 / 60), s = total % 60
  var ss = (s < 10 ? "0" : "") + s
  return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

// ---------------------------------------------------------------- colors

function _score(c) {
  return c.hslSaturation * (1 - Math.abs(c.hslLightness - 0.5) * 1.2)
}

function _lift(h, s, l, darkTheme, QtRef) {
  var sat = clamp(s * 1.15, 0.45, 0.85)
  var light = darkTheme ? clamp(l, 0.62, 0.74) : clamp(l, 0.34, 0.45)
  return QtRef.hsla(h, sat, light, 1)
}

function _hueDistance(a, b) {
  var d = Math.abs(a - b) % 1
  return Math.min(d, 1 - d)
}

// Two readable accents from a quantized palette: the most characterful color,
// plus the best one with a clearly different hue (or a gentle analogous shift
// of the first when the cover is all one hue). Lifted to read well: vivid,
// mid-light on dark themes, mid-dark on light ones. Null when the palette is
// too gray to theme from.
function accentPair(colors, darkTheme, QtRef) {
  var best = null, bestScore = -1
  for (var i = 0; i < colors.length; i++) {
    var c = colors[i]
    if (c.hslLightness < 0.08 || c.hslLightness > 0.95) continue
    var score = _score(c)
    if (score > bestScore) { bestScore = score; best = c }
  }
  if (!best || best.hslSaturation < 0.15) return null
  var h = Math.max(0, best.hslHue)

  var second = null, secondScore = -1
  for (var j = 0; j < colors.length; j++) {
    var o = colors[j]
    if (o === best || o.hslSaturation < 0.18 || o.hslLightness < 0.08 || o.hslLightness > 0.95) continue
    if (_hueDistance(Math.max(0, o.hslHue), h) < 0.08) continue
    var s2 = _score(o)
    if (s2 > secondScore) { secondScore = s2; second = o }
  }

  var a = _lift(h, best.hslSaturation, best.hslLightness, darkTheme, QtRef)
  var b = second
    ? _lift(Math.max(0, second.hslHue), second.hslSaturation, second.hslLightness, darkTheme, QtRef)
    : _lift((h + 0.07) % 1, best.hslSaturation, best.hslLightness, darkTheme, QtRef)
  return { a: a, b: b }
}

function mix(a, b, t, QtRef) {
  return QtRef.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                    a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
}

// ---------------------------------------------------------------- shapes

// Points along a rounded rectangle's outline, from the top middle going
// clockwise, stopping at `fraction` (0..1) of the way round. For a progress
// stroke drawn with PathPolyline. `inset` keeps a stroke inside w × h.
function outlinePoints(w, h, r, inset, fraction, QtRef) {
  var x0 = inset, y0 = inset, x1 = w - inset, y1 = h - inset
  var rad = Math.max(0, Math.min(r, (x1 - x0) / 2, (y1 - y0) / 2))
  var cx = w / 2
  function line(ax, ay, bx, by) {
    return { len: Math.hypot(bx - ax, by - ay), at: function(t) { return [ax + (bx - ax) * t, ay + (by - ay) * t] }, steps: 1 }
  }
  function arc(ox, oy, a0) {
    // Quarter circle clockwise (screen coordinates) starting at angle a0.
    return { len: Math.PI * rad / 2, steps: 6, at: function(t) {
      var a = a0 + t * Math.PI / 2
      return [ox + rad * Math.cos(a), oy + rad * Math.sin(a)]
    } }
  }
  var segs = [
    line(cx, y0, x1 - rad, y0),
    arc(x1 - rad, y0 + rad, -Math.PI / 2),
    line(x1, y0 + rad, x1, y1 - rad),
    arc(x1 - rad, y1 - rad, 0),
    line(x1 - rad, y1, x0 + rad, y1),
    arc(x0 + rad, y1 - rad, Math.PI / 2),
    line(x0, y1 - rad, x0, y0 + rad),
    arc(x0 + rad, y0 + rad, Math.PI),
    line(x0 + rad, y0, cx, y0)
  ]
  var total = 0
  for (var i = 0; i < segs.length; i++) total += segs[i].len
  var left = clamp(fraction, 0, 1) * total
  var pts = [QtRef.point(cx, y0)]
  for (var s = 0; s < segs.length && left > 0; s++) {
    var seg = segs[s]
    var upto = seg.len > 0 ? Math.min(1, left / seg.len) : 1
    for (var k = 1; k <= seg.steps; k++) {
      var t = Math.min(upto, k / seg.steps)
      var p = seg.at(t)
      pts.push(QtRef.point(p[0], p[1]))
      if (t >= upto) break
    }
    left -= seg.len
  }
  return pts
}

// Average of levels[from..to) or 0.
function band(levels, from, to) {
  if (!levels || levels.length === 0) return 0
  var a = Math.floor(from * levels.length), b = Math.max(a + 1, Math.floor(to * levels.length))
  var sum = 0, n = 0
  for (var i = a; i < b && i < levels.length; i++) { sum += levels[i]; n++ }
  return n ? sum / n : 0
}
