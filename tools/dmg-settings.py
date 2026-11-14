# dmgbuild ayarları (build-app.sh çağırır): dmgbuild -s tools/dmg-settings.py -D app=... -D bg=... "Mate Lyrics" çıktı.dmg
import os.path

app = defines["app"]
appname = os.path.basename(app)

volume_name = "Mate Lyrics"
format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "Resources/AppIcon.icns"
background = defines["bg"]

window_rect = ((240, 180), (600, 380))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 104
text_size = 13
arrange_by = None
icon_locations = {appname: (170, 175), "Applications": (430, 175)}
