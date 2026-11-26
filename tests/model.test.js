// Unit tests for Model.js (pure logic, no QML). Run: node tests/model.test.js
const fs = require('fs')
const path = require('path')
const assert = require('assert')

// Model.js is a QML `.pragma library`; drop that line and evaluate the rest.
const src = fs.readFileSync(path.join(__dirname, '..', 'Model.js'), 'utf8').replace(/^\.pragma library\s*$/m, '')
eval(src)

const P = (bus, extra) => Object.assign({ dbusName: 'org.mpris.MediaPlayer2.' + bus, trackTitle: 'Song', isPlaying: false }, extra)
const brave = P('brave.instance6236', { identity: 'Brave', isPlaying: true })
const zen = P('firefox.instance_1_85', { identity: 'Mozilla zen', desktopEntry: 'zen' })
const spotify = P('spotify', { identity: 'Spotify', desktopEntry: 'spotify' })
const proxy = P('playerctld', { identity: 'playerctld' })
const empty = P('vlc', { identity: 'VLC media player', trackTitle: '' })

// filterPlayers
assert.deepEqual(filterPlayers([brave, proxy, zen, empty, spotify]).map(key), [brave, zen, spotify].map(key))
assert.equal(filterPlayers([Object.assign({}, empty, { isPlaying: true })]).length, 1)   // playing, untitled: kept
assert.deepEqual(filterPlayers([brave, spotify], { skipSpotify: true }), [brave])
assert.deepEqual(filterPlayers(null), [])
assert.ok(!isProxy(P('playerctldx')))

// selectActive
assert.equal(selectActive([], '', {}), null)
assert.equal(selectActive([zen, brave], '', {}), brave)                         // playing beats paused
const zenPlaying = Object.assign({}, zen, { isPlaying: true })
assert.equal(selectActive([zenPlaying, brave], '', { [key(zenPlaying)]: 5, [key(brave)]: 9 }), brave)  // newest start
assert.equal(selectActive([zenPlaying, brave], '', { [key(zenPlaying)]: 10, [key(brave)]: 9 }), zenPlaying)
assert.equal(selectActive([zen, spotify], '', { [key(spotify)]: 3, [key(zen)]: 1 }), spotify)  // paused: most recent
assert.equal(selectActive([zen, spotify], '', {}), zen)                         // nothing known: first
assert.equal(selectActive([zen, brave], key(zen), {}), zen)                     // pinned wins
assert.equal(selectActive([brave], key(zen), {}), brave)                        // pin gone: fall back

// cycleKey
assert.equal(cycleKey([brave, zen, spotify], key(brave), 1), key(zen))
assert.equal(cycleKey([brave, zen, spotify], key(spotify), 1), key(brave))
assert.equal(cycleKey([brave, zen, spotify], key(brave), -1), key(spotify))
assert.equal(cycleKey([brave, zen], 'gone', 1), key(brave))
assert.equal(cycleKey([], 'x', 1), '')

// appName / appGlyph / desktopId
assert.equal(appName(brave), 'Brave')
assert.equal(appName(zen), 'Zen')
assert.equal(appName(spotify), 'Spotify')
assert.equal(appName(P('firefox', { identity: 'Mozilla firefox', desktopEntry: 'firefox' })), 'Firefox')
assert.equal(appName(P('mpv', { identity: 'mpv' })), 'mpv')
assert.equal(appName(P('io.github.Foo', { identity: 'mozilla foobar' })), 'Foobar')
assert.equal(appName(P('cider')), 'Cider')
assert.equal(appGlyph(spotify), '󰓇')
assert.equal(appGlyph(P('weird')), '󰝚')
assert.equal(desktopId(brave), 'brave-browser')
assert.equal(desktopId(zen), 'zen')
assert.equal(windowClass(zen), 'class:^(zen)$')
assert.equal(windowClass(P('org.gnome.Totem', { desktopEntry: 'org.gnome.Totem' })), 'class:^(org\\.gnome\\.Totem)$')

// cleanText / safeArtUrl
assert.equal(cleanText('Hello\nWorld\x07\t!'), 'Hello World !')
assert.equal(safeArtUrl('https://i.scdn.co/image/abc'), 'https://i.scdn.co/image/abc')
assert.equal(safeArtUrl('http://localhost:8080/cover.jpg'), 'http://localhost:8080/cover.jpg')
assert.equal(safeArtUrl('file:///home/user/cover.png'), 'file:///home/user/cover.png')
assert.equal(safeArtUrl('data:image/png;base64,AAAA'), 'data:image/png;base64,AAAA')
assert.equal(safeArtUrl('ftp://evil.example/a.png'), '')
assert.equal(safeArtUrl('image://theme/icon'), '')
assert.equal(safeArtUrl('data:text/html;base64,AAAA'), '')
assert.equal(safeArtUrl('http://169.254.169.254/latest/meta-data'), '')

// siteName
assert.equal(siteName('https://www.youtube.com/watch?v=x'), 'YouTube')
assert.equal(siteName('https://music.youtube.com/watch?v=x'), 'YouTube Music')
assert.equal(siteName('https://m.soundcloud.com/a'), 'SoundCloud')
assert.equal(siteName('https://foo.bandcamp.com/track/x'), 'Bandcamp')
assert.equal(siteName('https://example.org/x'), 'Example')
assert.equal(siteName('https://poridhi.io/course'), 'Poridhi')
assert.equal(siteName('https://www.bbc.co.uk/x'), 'BBC')
assert.equal(siteName('https://www.instagram.com/reel/x'), 'Instagram')
assert.equal(siteName('https://www.tiktok.com/@a/video/1'), 'TikTok')
assert.equal(siteName('https://web.whatsapp.com/'), 'WhatsApp')
assert.equal(siteName('https://www.dailymotion.com/video/x'), 'Dailymotion')
assert.equal(siteName('https://old.reddit.com/r/x'), 'Reddit')
assert.equal(siteName('https://www.facebook.com/watch'), 'Facebook')
assert.equal(siteName('https://x.com/a/status/1'), 'X')

// siteFromTitle
assert.equal(siteFromTitle('(209) All Code Is Slop — Lauren Tan - YouTube - Brave'), 'YouTube')
assert.equal(siteFromTitle('Reel | Instagram — Zen Browser'), 'Instagram')
assert.equal(siteFromTitle('Hacker News — Zen Browser'), '')
assert.equal(siteFromTitle('TikTok - Make Your Day - Brave'), '')
assert.equal(siteFromTitle(''), '')
assert.equal(siteGlyph('YouTube'), '󰗃')
assert.equal(siteGlyph('Poridhi'), '')

// isGenericTitle / ago
assert.ok(isGenericTitle('Instagram'))
assert.ok(isGenericTitle('Facebook', 'Facebook'))
assert.ok(isGenericTitle('ok'))
assert.ok(!isGenericTitle('Hoor (Official Video)'))
assert.equal(ago(30000), 'just now')
assert.equal(ago(7300000), '2 h ago')
assert.equal(siteName('file:///home/x.mp3'), '')
assert.equal(siteName(undefined), '')

// timestamp
assert.equal(timestamp(0), '0:00')
assert.equal(timestamp(65.9), '1:05')
assert.equal(timestamp(3725), '1:02:05')
assert.equal(timestamp(NaN), '0:00')
assert.equal(timestamp(-4), '0:00')

// pickWindow
const wins = [
  { appId: 'foot', title: 'Hoor' },
  { appId: 'zen', title: 'Hacker News — Zen Browser' },
  { appId: 'zen', title: 'Hoor (Official Video) - YouTube — Zen Browser' },
  { appId: 'brave-browser', title: 'Song - YouTube - Brave' }
]
assert.equal(pickWindow(wins, 'zen', 'Hoor (Official Video)'), 2)
assert.equal(pickWindow(wins, 'zen', 'Something else'), -1)          // no guessing
assert.equal(pickWindow(wins.concat([{ appId: 'zen', title: 'Instagram — Zen Browser' }]), 'zen', 'Instagram'), -1)  // generic
assert.equal(pickWindow(wins, 'brave-browser', 'Song'), 3)
assert.equal(pickWindow(wins.concat([{ appId: 'zen', title: 'Picture-in-Picture' }]), 'zen', 'Hoor'), 4)
assert.equal(pickWindow(wins, 'mpv', 'x'), -1)
assert.equal(pickWindow(wins, '', 'x'), -1)
assert.equal(pickWindow(null, 'zen', 'x'), -1)

// #15839: two PiP windows sharing the same appId must not blindly pick the first PiP
const twoPips = [
  { appId: 'firefox', title: 'Picture-in-Picture' },
  { appId: 'firefox', title: 'Picture-in-Picture' },
  { appId: 'firefox', title: 'Dashboard — Mozilla Firefox' }
]
assert.equal(pickWindow(twoPips, 'firefox', 'Some Video Title'), -1)
// Two PiPs with an unambiguous matching non-PiP tab can mirror the verified tab
assert.equal(pickWindow(twoPips.concat([{ appId: 'firefox', title: 'Hoor (Official Video) - YouTube — Mozilla Firefox' }]), 'firefox', 'Hoor (Official Video)'), 3)
// Two titled PiP windows pick only the matching PiP
const titledPips = [
  { appId: 'firefox', title: 'Picture-in-Picture - Private Session' },
  { appId: 'firefox', title: 'Picture-in-Picture - Hoor (Official Video)' }
]
assert.equal(pickWindow(titledPips, 'firefox', 'Hoor (Official Video)'), 1)
// Generic or empty track titles never capture an untitled PiP, nor do multiple same-app browser instances
assert.equal(pickWindow([{ appId: 'firefox', title: 'Picture-in-Picture' }], 'firefox', 'Instagram'), -1)
assert.equal(pickWindow([{ appId: 'firefox', title: 'Picture-in-Picture' }], 'firefox', ''), -1)
assert.equal(pickWindow([{ appId: 'firefox', title: 'Picture-in-Picture' }], 'firefox', 'Hoor (Official Video)', 2), -1)
// Two non-PiP windows matching the same title are ambiguous
assert.equal(pickWindow([
  { appId: 'firefox', title: 'Hoor (Official Video) — Mozilla Firefox' },
  { appId: 'firefox', title: 'Hoor (Official Video) — Mozilla Firefox' }
], 'firefox', 'Hoor (Official Video)'), -1)

// showsTrack: generic PiP still matches, titled PiP must match track, clamp handles NaN
assert.ok(showsTrack('(209) Ye Fitoor Mera - Arijit Singh - YouTube — Zen Browser', 'Ye Fitoor Mera - Arijit Singh'))
assert.ok(!showsTrack('Hacker News — Zen Browser', 'Ye Fitoor Mera'))
assert.ok(showsTrack('Picture-in-Picture', 'anything'))
assert.ok(!showsTrack('Picture-in-Picture - Other Video — Mozilla Firefox', 'Hoor'))
assert.ok(showsTrack('Whatever', ''))
assert.ok(isVideoTitleVerified({ title: 'Hoor (Official Video) - YouTube — Zen Browser' }, 'Hoor (Official Video)'))
assert.ok(!isVideoTitleVerified({ title: 'Picture-in-Picture' }, 'Hoor (Official Video)'))
assert.equal(pickWindow([{ appId: 'zen-browser', title: 'Hoor (Official Video) — Zen Browser' }], 'zen', 'Hoor (Official Video)'), 0)
assert.equal(clamp(NaN, 0, 1), 0)

// clampView / zoomAt (content 400x200 in a 400x225 viewport)
let v = clampView({ zoom: 1, x: -50, y: -50 }, 400, 200, 400, 225)
assert.deepEqual(v, { zoom: 1, x: 0, y: 12.5 })                  // smaller: centered
v = zoomAt({ zoom: 1, x: 0, y: 12.5 }, 2, 200, 112.5, 400, 200, 400, 225)
assert.equal(v.zoom, 2); assert.equal(v.x, -200)                  // zoom about the center
v = clampView({ zoom: 2, x: 100, y: -999 }, 400, 200, 400, 225)
assert.equal(v.x, 0); assert.equal(v.y, 225 - 400)                // pinned to the edges
assert.equal(zoomAt({ zoom: 8, x: 0, y: 0 }, 2, 0, 0, 400, 200, 400, 225).zoom, 8)
assert.equal(zoomAt({ zoom: 1, x: 0, y: 0 }, 0.5, 0, 0, 400, 200, 400, 225).zoom, 1)

// filterPlayers: a source between tracks is held
assert.equal(filterPlayers([empty], { keep: key(empty) }).length, 1)
assert.equal(filterPlayers([empty], { keep: 'other' }).length, 0)

// siteFromTitle: "on <Site>", " : " separators; siteFromTrack; siteGuess
assert.equal(siteFromTitle('Explore - Find your favorite videos on TikTok - Chromium'), 'TikTok')
assert.equal(siteFromTitle('Planet Money : Instagram'), 'Instagram')
assert.equal(siteFromTrack('KICK'), 'Kick')
assert.equal(siteFromTrack('Instagram'), 'Instagram')
assert.equal(siteFromTrack('Hoor (Official Video)'), '')
assert.equal(siteGuess('What is PeerTube? - Framatube - Chromium', 'What is PeerTube?', ''), 'Framatube')
assert.equal(siteGuess('The Europa Concept | NASA+ - Chromium', 'The Europa Concept', ''), 'NASA+')
assert.equal(siteGuess('Hoor - Atif Aslam — Zen Browser', 'Hoor', 'Atif Aslam'), '')          // artist, not a site
assert.equal(siteGuess('Video.js | Open Source Video Player - Chromium', 'Video.js', ''), '')  // a tagline
assert.equal(siteGuess('Something else - Site', 'Hoor (Official)', ''), '')                    // other tab
assert.equal(siteGuess('Live TV — DW English - Chromium', 'Live TV', ''), 'DW English')

// siteName: proper names for common sites; hosted subdomains
assert.equal(siteName('https://9gag.com/'), '9GAG')
assert.equal(siteName('https://plus.nasa.gov/video'), 'NASA')
assert.equal(siteName('https://somafm.com/player/'), 'SomaFM')
assert.equal(siteName('https://archive.org/details/x'), 'Internet Archive')
assert.equal(siteName('https://shaka-player-demo.appspot.com/demo/'), 'Shaka Player Demo')
assert.equal(siteName('https://iammhador.github.io/x'), 'Iammhador')
assert.equal(siteName('https://poridhi.io/x'), 'Poridhi')
// looksLive
assert.ok(looksLive('Anything', 'Twitch'))
assert.ok(looksLive('🔴 LIVE: Somoy TV News', 'YouTube'))
assert.ok(looksLive('DW News livestream', ''))
assert.ok(!looksLive('Big Buck Bunny 60fps 4K', 'YouTube'))
assert.ok(!looksLive('Oliver - Delivered', 'YouTube'))
// demoOnly
assert.deepEqual(filterPlayers([brave, P('mpv.demo')], { demoOnly: true }).map(key), ['org.mpris.MediaPlayer2.mpv.demo'])
console.log('model tests passed')
