from pathlib import Path
import datetime, email.utils, hashlib, json, plistlib, subprocess, sys
from xml.etree import ElementTree as ET

root = Path(__file__).resolve().parent.parent
output = Path(sys.argv[1]).resolve()
info = plistlib.loads((root/'Resources/Info.plist').read_bytes())
version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
project = info['LTProjectURL']
archive = output/f'LightTranslate-{version}-arm64.zip'
account = 'com.local.LightTranslate.sparkle'
tools = root/'.build/artifacts/translating/Sparkle/bin'

def run(*args):
    return subprocess.check_output([str(tools/'sign_update'), '--account', account, *map(str, args)], text=True).strip()

signature = run('-p', archive)
run('--verify', archive, signature)
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
rss = ET.Element('rss', {'version': '2.0'})
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = '轻译更新'
ET.SubElement(channel, 'link').text = project
ET.SubElement(channel, 'language').text = 'zh-cn'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f'轻译 {version}'
ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
ET.SubElement(item, f'{{{ns}}}version').text = build
ET.SubElement(item, f'{{{ns}}}shortVersionString').text = version
ET.SubElement(item, f'{{{ns}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
ET.SubElement(item, 'description').text = '原生液态玻璃界面；等待时仅显示一行小窗；译文返回后展开。'
ET.SubElement(item, 'enclosure', {'url': f'{project}/releases/download/v{version}/{archive.name}',
    'length': str(archive.stat().st_size), 'type': 'application/octet-stream', f'{{{ns}}}edSignature': signature})
ET.indent(rss, space='  ')
appcast = output/'appcast.xml'
ET.ElementTree(rss).write(appcast, encoding='utf-8', xml_declaration=True)
run(appcast, '--disable-signing-warning')
run('--verify', appcast)
files = sorted(output.glob('*.zip')) + sorted(output.glob('*.dmg')) + [appcast]
checksums = '\n'.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}' for p in files) + '\n'
(output/'SHA256SUMS.txt').write_text(checksums)
manifest = {'version': version, 'build': build, 'architecture': 'arm64', 'minimumMacOS': info['LSMinimumSystemVersion'],
    'project': project, 'updateFeed': info['SUFeedURL'], 'updateSignature': 'Ed25519',
    'appleSigning': 'Developer ID' if __import__('os').environ.get('SIGNING_IDENTITY') else 'ad-hoc',
    'notarized': bool(__import__('os').environ.get('NOTARY_PROFILE')), 'files': [p.name for p in files]}
(output/'release.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print('PASS: archive and appcast signatures verified')
