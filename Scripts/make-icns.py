from pathlib import Path
import struct

root = Path(__file__).resolve().parent.parent / '.build/release-assets'
entries = [('ic07', 'icon_128x128.png'), ('ic08', 'icon_256x256.png'),
           ('ic09', 'icon_512x512.png'), ('ic10', 'icon_512x512@2x.png')]
chunks = []
for kind, name in entries:
    data = (root / 'AppIcon.iconset' / name).read_bytes()
    chunks.append(kind.encode('ascii') + struct.pack('>I', len(data) + 8) + data)
body = b''.join(chunks)
(root / 'AppIcon.icns').write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
