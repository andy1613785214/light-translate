from pathlib import Path
import sys
from ds_store import DSStore
from mac_alias import Alias

mount = Path(sys.argv[1]).resolve()
background = Alias.for_file(str(mount / '.background/background.png'))
# Resolve by the image's own volume identity and relative target; never embed the build mount path.
background.volume.posix_path = None
with DSStore.open(str(mount / '.DS_Store'), 'w+') as store:
    store['.']['bwsp'] = {'ShowStatusBar': False, 'ShowToolbar': False, 'ShowPathbar': False,
                         'ShowSidebar': False, 'ContainerShowSidebar': False,
                         'WindowBounds': '{{120, 120}, {540, 360}}', 'SidebarWidth': 0}
    store['.']['icvp'] = {'viewOptionsVersion': 1, 'backgroundType': 2,
                         'backgroundImageAlias': background.to_bytes(),
                         'iconSize': 80.0, 'textSize': 13.0, 'gridSpacing': 100.0,
                         'gridOffsetX': 0.0, 'gridOffsetY': 0.0, 'arrangeBy': 'none',
                         'showIconPreview': True, 'showItemInfo': False, 'labelOnBottom': True}
    store['.']['vstl'] = ('type', b'icnv')
    store['轻译.app']['Iloc'] = (158, 178)
    store['Applications']['Iloc'] = (382, 178)
