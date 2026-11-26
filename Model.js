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
  // A source between two tracks (YouTube's autoplay countdown, a click to
  // another video) reports "Stopped" with no title for a moment. `keep` is
  // the one being held through that gap, so the bar and card don't vanish.
  var keep = opts && opts.keep ? String(opts.keep) : ""
  // Screenshot mode: only the fake players from tools/fake-player.py.
  var demoOnly = !!(opts && opts.demoOnly)
  for (var i = 0; i < (players ? players.length : 0); i++) {
    var p = players[i]
    if (!p || isProxy(p)) continue
    if (skipSpotify && isSpotify(p)) continue
    if (demoOnly && !/\.demo$/.test(String(p.dbusName || ""))) continue
    if (String(p.trackTitle || "").trim() === "" && !p.isPlaying && (keep === "" || key(p) !== keep)) continue
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

function _isPipTitle(title) {
  return /\bpicture[- ]in[- ]picture\b/.test(String(title || "").toLowerCase())
}

// The window showing this player's video, as an index into `windows`
// ([{appId, title}]), or -1 when it can't be told for sure. A
// Picture-in-Picture window is preferred when unambiguous, otherwise the
// single window whose active tab holds the non-generic track title.
// Multiple PiP windows or multiple same-app instances require the track
// title in the PiP title itself so unrelated private windows never leak.
function pickWindow(windows, appId, trackTitle, sameAppPlayers) {
  var want = String(appId || "").toLowerCase()
  if (!windows || want === "") return -1
  var generic = isGenericTitle(trackTitle, "")
  var t = String(trackTitle || "").toLowerCase().trim().slice(0, 40)
  var pip = []
  var pipMatched = []
  var titled = []
  for (var i = 0; i < windows.length; i++) {
    var w = windows[i]
    if (!w || String(w.appId || "").toLowerCase() !== want) continue
    var title = String(w.title || "").toLowerCase()
    if (_isPipTitle(title)) {
      pip.push(i)
      if (!generic && t !== "" && title.indexOf(t) !== -1) pipMatched.push(i)
      continue
    }
    if (!generic && t !== "" && title.indexOf(t) !== -1) titled.push(i)
  }
  if (pipMatched.length === 1) return pipMatched[0]
  if (pipMatched.length > 1) return -1
  if (pip.length === 1 && !generic && t !== "" && !(Number(sameAppPlayers) > 1)) return pip[0]
  if (titled.length === 1) return titled[0]
  return -1
}

// Whether a window title (the browser's active tab) is this track: if not,
// the video plays in a background tab and a mirror would show another page.
function showsTrack(windowTitle, trackTitle) {
  var t = String(trackTitle || "").toLowerCase().trim().slice(0, 40)
  var w = String(windowTitle || "").toLowerCase().trim()
  if (t === "") return true
  if (_isPipTitle(w)) {
    var rest = _stripBrowser(w).replace(/\bpicture[- ]in[- ]picture\b/, "").replace(/^[\s\-—–|•·:]+|[\s\-—–|•·:]+$/g, "")
    return rest === "" || rest.indexOf(t) !== -1
  }
  return w.indexOf(t) !== -1
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
  "tidal.com": ["TIDAL", "󰝚"], "youtube-nocookie.com": ["YouTube", "󰗃"], "mixcloud.com": ["Mixcloud", "󰝚"],
  "music.amazon.com": ["Amazon Music", "󰝚"], "podcasts.apple.com": ["Apple Podcasts", "󰦔"],
  "pocketcasts.com": ["Pocket Casts", "󰦔"], "audible.com": ["Audible", "󰋋"], "audiomack.com": ["Audiomack", "󰝚"],
  "jiosaavn.com": ["JioSaavn", "󰝚"], "gaana.com": ["Gaana", "󰝚"], "anghami.com": ["Anghami", "󰝚"],
  "jamendo.com": ["Jamendo", "󰝚"], "tunein.com": ["TuneIn", "󰐹"], "somafm.com": ["SomaFM", "󰐹"],
  "radio.garden": ["Radio Garden", "󰐹"], "npr.org": ["NPR", "󰐹"], "bbc.co.uk": ["BBC", "󰐹"], "bbc.com": ["BBC", "󰐹"],
  "ted.com": ["TED", "󰕧"], "archive.org": ["Internet Archive", "󰕧"], "nasa.gov": ["NASA", "󰕧"],
  "9gag.com": ["9GAG", "󰕧"], "imgur.com": ["Imgur", "󰕧"], "streamable.com": ["Streamable", "󰕧"],
  "rumble.com": ["Rumble", "󰕧"], "odysee.com": ["Odysee", "󰕧"], "bilibili.com": ["Bilibili", "󰕧"],
  "nicovideo.jp": ["Niconico", "󰕧"], "vk.com": ["VK", "󰕧"], "vkvideo.ru": ["VK Video", "󰕧"],
  "khanacademy.org": ["Khan Academy", "󰑴"], "w3schools.com": ["W3Schools", "󰑴"], "dw.com": ["DW", "󰕧"],
  "aljazeera.com": ["Al Jazeera", "󰕧"], "euronews.com": ["Euronews", "󰕧"], "crunchyroll.com": ["Crunchyroll", "󰕧"],
  "hulu.com": ["Hulu", "󰕧"], "max.com": ["Max", "󰕧"], "tv.apple.com": ["Apple TV", "󰕧"], "zee5.com": ["ZEE5", "󰕧"],
  "sonyliv.com": ["SonyLIV", "󰕧"], "jiohotstar.com": ["JioHotstar", "󰕧"], "toffeelive.com": ["Toffee", "󰕧"],
  "binge.buzz": ["Binge", "󰕧"], "prothomalo.com": ["Prothom Alo", "󰕧"], "somoynews.tv": ["Somoy TV", "󰕧"],
  "jamuna.tv": ["Jamuna TV", "󰕧"], "pexels.com": ["Pexels", "󰕧"], "pixabay.com": ["Pixabay", "󰕧"],
  "videojs.com": ["Video.js", "󰕧"], "plyr.io": ["Plyr", "󰕧"], "plex.tv": ["Plex", "󰕧"], "coub.com": ["Coub", "󰕧"]
}

// Hosts that serve many unrelated sites: the subdomain is the site's name
// ("shaka-player-demo.appspot.com" -> "Shaka Player Demo").
var HOSTED = /\.(github\.io|gitlab\.io|netlify\.app|vercel\.app|pages\.dev|appspot\.com|web\.app|firebaseapp\.com|herokuapp\.com|blogspot\.com|onrender\.com|fly\.dev)$/

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
  if (HOSTED.test(host)) {
    var sub = host.replace(HOSTED, "").split(".").pop()
    return sub.split(/[-_]+/).filter(function(w) { return w !== "" })
      .map(function(w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join(" ")
  }
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
  var m = /(?:\s[-—–|•·:]\s|^)([^-—–|•·:]+)$/.exec(t)
  var last = m ? m[1].trim().toLowerCase() : ""
  if (last === "") return ""
  // "Explore - Find your favorite videos on TikTok"
  var on = /\bon ([a-z0-9+.' ]{2,20})$/.exec(last)
  for (var h in SITES) {
    var n = SITES[h][0].toLowerCase()
    if (n === last || (on && on[1] === n)) return SITES[h][0]
  }
  return ""
}

// A known site named by the track title itself ("Instagram", "KICK"): some
// sites give no better title than their own name.
function siteFromTrack(trackTitle) {
  var t = String(trackTitle || "").trim().toLowerCase()
  if (t === "") return ""
  for (var h in SITES) if (SITES[h][0].toLowerCase() === t) return SITES[h][0]
  return ""
}

// An unknown site's name from the tail of its window title, when the title
// is "<track> - <Site>": "What is PeerTube? - Framatube" -> "Framatube".
// Only a short name that isn't the artist, so "Song - Artist" stays unnamed.
function siteGuess(windowTitle, trackTitle, artist) {
  var w = _stripBrowser(windowTitle).trim()
  var t = String(trackTitle || "").trim()
  if (t.length < 4 || w.toLowerCase().indexOf(t.toLowerCase()) !== 0) return ""
  var m = /^\s*(?:[-—–|•·:])\s+(.+)$/.exec(w.slice(t.length))
  if (!m) return ""
  var name = m[1].trim()
  if (name.length < 2 || name.length > 20 || name.split(/\s+/).length > 2) return ""
  if (!/^[A-Z0-9]/.test(name) || /[-—–|•·:]/.test(name)) return ""
  if (artist && name.toLowerCase() === String(artist).trim().toLowerCase()) return ""
  return name
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

// Whether a track with no length is a live stream: the site only streams
// live, or the title says so. Otherwise it's a player not sharing a length.
function looksLive(title, site) {
  if (/^(twitch|kick)$/i.test(String(site || ""))) return true
  return /\blive\b|🔴|\blivestream\b|\bon air\b|লাইভ|সরাসরি/i.test(String(title || ""))
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
  var n = Number(value)
  if (!isFinite(n)) return min
  return Math.max(min, Math.min(max, n))
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
