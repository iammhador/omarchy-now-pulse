#!/usr/bin/env python3
"""A fake MPRIS player, for testing Now Pulse and taking screenshots without
real music or real cover art.

    python3 tools/fake-player.py                 # "Demo" player, 3 made-up tracks
    python3 tools/fake-player.py --name zen --identity "Mozilla zen" \
        --desktop zen --url https://www.youtube.com/watch?v=demo

Covers are generated gradients (ImageMagick `magick`), cached in
~/.cache/now-pulse-demo. Next / Previous / PlayPause / Seek / Volume work.
Send SIGUSR1 to skip to the next track from a script. Ctrl+C to quit.
"""
import argparse
import os
import signal
import subprocess
import time

from gi.repository import Gio, GLib

TRACKS = [
    ("Paper Lanterns", "Mira Vale", "Night Market", "#f6a04d", "#7c3aed", 214),
    ("Glass Harbour", "The Low Tides", "Harbour Lights", "#22d3ee", "#1e3a8a", 187),
    ("Saffron Hours", "Ayaan Rahman", "Monsoon Letters", "#facc15", "#dc2626", 241),
    ("Quiet Machines", "Northwind", "Signals", "#34d399", "#0f766e", 199),
]

XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/><method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/><property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/><property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/><property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/><method name="Previous"/><method name="Pause"/><method name="PlayPause"/>
    <method name="Stop"/><method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition"><arg direction="in" name="TrackId" type="o"/><arg direction="in" name="Position" type="x"/></method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/><property name="LoopStatus" type="s" access="readwrite"/>
    <property name="Rate" type="d" access="readwrite"/><property name="Shuffle" type="b" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/><property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/><property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/><property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/><property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/><property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""


def cover(i, a, b):
    d = os.path.expanduser("~/.cache/now-pulse-demo")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, f"cover-{i}.png")
    if not os.path.exists(path):
        subprocess.run(["magick", "-size", "600x600", f"gradient:{a}-{b}",
                        "(", "-size", "600x600", "radial-gradient:#ffffff55-#00000000", ")",
                        "-compose", "screen", "-composite", path], check=False)
    return "file://" + path


class Player:
    def __init__(self, args):
        self.a = args
        self.i = 0
        self.playing = True
        self.started = time.monotonic()
        self.offset = 0.0
        self.volume = 0.7
        self.shuffle = False
        self.loop = "None"
        self.conn = None

    # ---- state
    def pos(self):
        p = self.offset + (time.monotonic() - self.started if self.playing else 0)
        return min(p, TRACKS[self.i][5])

    def meta(self):
        t, ar, al, ca, cb, ln = TRACKS[self.i]
        m = {
            "mpris:trackid": GLib.Variant("o", f"/demo/track/{self.i}"),
            "xesam:title": GLib.Variant("s", t),
            "xesam:artist": GLib.Variant("as", [ar]),
            "xesam:album": GLib.Variant("s", al),
            "mpris:artUrl": GLib.Variant("s", cover(self.i, ca, cb)),
        }
        if not self.a.no_length:
            m["mpris:length"] = GLib.Variant("x", ln * 1_000_000)
        if self.a.url:
            m["xesam:url"] = GLib.Variant("s", self.a.url)
        return m

    def props(self):
        return {
            "org.mpris.MediaPlayer2": {
                "CanQuit": GLib.Variant("b", True), "CanRaise": GLib.Variant("b", False),
                "HasTrackList": GLib.Variant("b", False), "Identity": GLib.Variant("s", self.a.identity),
                "DesktopEntry": GLib.Variant("s", self.a.desktop),
                "SupportedUriSchemes": GLib.Variant("as", []), "SupportedMimeTypes": GLib.Variant("as", []),
            },
            "org.mpris.MediaPlayer2.Player": {
                "PlaybackStatus": GLib.Variant("s", "Playing" if self.playing else "Paused"),
                "LoopStatus": GLib.Variant("s", self.loop), "Rate": GLib.Variant("d", 1.0),
                "Shuffle": GLib.Variant("b", self.shuffle), "Metadata": GLib.Variant("a{sv}", self.meta()),
                "Volume": GLib.Variant("d", self.volume), "Position": GLib.Variant("x", int(self.pos() * 1_000_000)),
                "MinimumRate": GLib.Variant("d", 1.0), "MaximumRate": GLib.Variant("d", 1.0),
                "CanGoNext": GLib.Variant("b", True), "CanGoPrevious": GLib.Variant("b", True),
                "CanPlay": GLib.Variant("b", True), "CanPause": GLib.Variant("b", True),
                "CanSeek": GLib.Variant("b", not self.a.no_length), "CanControl": GLib.Variant("b", True),
            },
        }

    def changed(self, iface, names):
        p = self.props()[iface]
        body = GLib.Variant("(sa{sv}as)", (iface, {n: p[n] for n in names}, []))
        self.conn.emit_signal(None, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties",
                              "PropertiesChanged", body)

    def set_track(self, i):
        self.i = i % len(TRACKS)
        self.offset = 0.0
        self.started = time.monotonic()
        self.changed("org.mpris.MediaPlayer2.Player", ["Metadata", "PlaybackStatus"])

    def set_playing(self, on):
        if on == self.playing:
            return
        self.offset = self.pos()
        self.started = time.monotonic()
        self.playing = on
        self.changed("org.mpris.MediaPlayer2.Player", ["PlaybackStatus"])

    # ---- dbus
    def call(self, conn, sender, path, iface, method, params, inv):
        if method == "Next":
            self.set_track(self.i + 1)
        elif method == "Previous":
            self.set_track(self.i - 1)
        elif method == "PlayPause":
            self.set_playing(not self.playing)
        elif method in ("Pause", "Stop"):
            self.set_playing(False)
        elif method == "Play":
            self.set_playing(True)
        elif method == "Seek":
            self.offset = max(0, self.pos() + params.unpack()[0] / 1e6)
            self.started = time.monotonic()
            conn.emit_signal(None, path, iface, "Seeked", GLib.Variant("(x)", (int(self.pos() * 1e6),)))
        elif method == "SetPosition":
            self.offset = max(0, params.unpack()[1] / 1e6)
            self.started = time.monotonic()
            conn.emit_signal(None, path, iface, "Seeked", GLib.Variant("(x)", (int(self.pos() * 1e6),)))
        elif method == "Quit":
            GLib.idle_add(loop.quit)
        inv.return_value(None)

    def get(self, conn, sender, path, iface, name):
        return self.props()[iface][name]

    def set(self, conn, sender, path, iface, name, value):
        if name == "Volume":
            self.volume = max(0.0, min(1.0, value.unpack()))
        elif name == "Shuffle":
            self.shuffle = value.unpack()
        elif name == "LoopStatus":
            self.loop = value.unpack()
        self.changed(iface, [name])
        return True


ap = argparse.ArgumentParser()
ap.add_argument("--name", default="demo", help="bus name suffix: org.mpris.MediaPlayer2.<name>")
ap.add_argument("--identity", default="Demo Player")
ap.add_argument("--desktop", default="")
ap.add_argument("--url", default="", help="xesam:url, as browsers send")
ap.add_argument("--track", type=int, default=0)
ap.add_argument("--no-length", action="store_true", help="send no length, like Zen / Firefox")
args = ap.parse_args()

player = Player(args)
player.i = args.track % len(TRACKS)
node = Gio.DBusNodeInfo.new_for_xml(XML)
loop = GLib.MainLoop()


def on_bus(conn, name):
    player.conn = conn
    for iface in node.interfaces:
        conn.register_object("/org/mpris/MediaPlayer2", iface, player.call, player.get, player.set)


Gio.bus_own_name(Gio.BusType.SESSION, "org.mpris.MediaPlayer2." + args.name, Gio.BusNameOwnerFlags.NONE,
                 on_bus, None, lambda *a: loop.quit())
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR1, lambda: (player.set_track(player.i + 1), True)[1])
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, lambda: (loop.quit(), False)[1])
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, lambda: (loop.quit(), False)[1])
loop.run()
