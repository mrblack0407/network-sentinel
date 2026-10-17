# dmgbuild settings for the Network Sentinel disk image.
#
# Used by scripts/make-dmg.sh:
#   build/dmgbuild-venv/bin/dmgbuild -s scripts/dmg-settings.py \
#       -D app=<path/to/Network Sentinel.app> -D background=<path/to/Background.tiff> \
#       "Network Sentinel" <output.dmg>
#
# The app and background paths come in through -D, so nothing here is tied to a
# checkout. dmgbuild writes the Finder view options straight into .DS_Store;
# no AppleScript is involved, so the build also works on CI runners.

app = defines["app"]
app_name = defines.get("app_name", "Network Sentinel.app")

files = [(app, app_name)]
symlinks = {"Applications": "/Applications"}

# Background artwork is 660 x 400 points and drawn from the top-left of the
# content view; icon centers share its horizontal midline.
background = defines["background"]
window_rect = ((100, 100), (660, 400))

icon_locations = {
    app_name: (180, 190),
    "Applications": (480, 190),
}

show_toolbar = False
show_sidebar = False
show_pathbar = True
show_status_bar = False

default_view = "icon-view"
icon_size = 128
text_size = 13

format = "UDZO"
filesystem = "HFS+"
