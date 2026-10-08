"""Validate the exported ad-hoc IPA and generate a versioned OTA installation page."""
import datetime
import hashlib
import html
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import zipfile

output = Path(os.environ['RUNNER_TEMP']) / 'export'
ipa = output / 'AgentOS.ipa'
backend = os.environ['BACKEND']
assert backend in ('test', 'production-creation')
with zipfile.ZipFile(ipa) as archive:
    infos = [n for n in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
    assert len(infos) == 1
    info = plistlib.loads(archive.read(infos[0]))
    profile_bytes = archive.read(infos[0].removesuffix('Info.plist') + 'embedded.mobileprovision')
assert info['CFBundleIdentifier'] == 'com.agentosplus.app'
build = str(info['CFBundleVersion'])
assert build == os.environ['BUILD_NUM'], f'Exported IPA build {build} differs from requested {os.environ["BUILD_NUM"]}'
version = str(info['CFBundleShortVersionString'])
profile_path = Path(os.environ['RUNNER_TEMP']) / 'exported.mobileprovision'
profile_path.write_bytes(profile_bytes)
profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(profile_path)]))
assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
assert profile.get('ProvisionedDevices'), 'Ad-hoc device list is empty'
assert not profile.get('ProvisionsAllDevices', False)
assert profile['Entitlements']['application-identifier'].endswith('.com.agentosplus.app')
assert not profile['Entitlements'].get('get-task-allow', False)

# Verify the signed application, not just the source entitlements or profile.
import tempfile
with tempfile.TemporaryDirectory(prefix='aihey-signed-check-') as extracted:
    with zipfile.ZipFile(ipa) as archive:
        archive.extractall(extracted)
    app_path = Path(extracted) / infos[0].removesuffix('/Info.plist')
    signed = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(app_path)], stderr=subprocess.PIPE))
    domains = signed.get('com.apple.developer.associated-domains', [])
    assert 'applinks:coder.tybbtech.com' in domains, 'Signed App is missing Coder domain association'
assert profile['Entitlements'].get('com.apple.developer.associated-domains'), 'Profile does not allow Associated Domains'

folder = f'{backend}-{build}-{os.environ["GITHUB_RUN_ID"]}-{os.environ["GITHUB_RUN_ATTEMPT"]}'
assert re.fullmatch(r'[a-z0-9-]+', folder)
base = 'https://agentos.tybbtech.com:3201/test-install/' + folder
name = f'AgentOS-{backend}-{build}.ipa'
ipa.rename(output / name)
label = '生产创作验收（积分购买关闭）' if backend == 'production-creation' else '测试服验收'
manifest = {'items': [{'assets': [{'kind': 'software-package', 'url': base + '/' + name}], 'metadata': {
    'bundle-identifier': info['CFBundleIdentifier'], 'bundle-version': build,
    'kind': 'software', 'title': 'AIHEY ' + label}}]}
(output / 'manifest.plist').write_bytes(plistlib.dumps(manifest))
page = f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>AIHEY 验收安装</title>
<style>body{{font:17px -apple-system,sans-serif;max-width:480px;margin:60px auto;padding:24px;line-height:1.7}}a{{display:block;background:#1672ed;color:white;padding:16px;text-align:center;border-radius:12px;text-decoration:none}}</style>
<h1>AIHEY</h1><h2>{html.escape(label)}</h2><p>版本 {html.escape(version)} · 构建 {html.escape(build)}</p>
<p>{'使用生产账号和现有积分验证真实创作。' if backend == 'production-creation' else '使用测试账号验证，连接测试服务。'}</p>
<a href="itms-services://?action=download-manifest&amp;url={base}/manifest.plist">安装验收包</a>
<p>请用已登记的 iPhone 在 Safari 中打开。同包名版本会替换当前安装；切换环境后请核对登录账号。</p></html>'''
(output / 'install.html').write_text(page, encoding='utf8')
report = {'version': version, 'build': build, 'backend': backend, 'deviceCount': len(profile['ProvisionedDevices']),
          'associatedDomains': domains, 'profileExpires': profile['ExpirationDate'].isoformat(), 'sha256': hashlib.sha256((output / name).read_bytes()).hexdigest(),
          'installUrl': base + '/install.html'}
(output / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
with open(os.environ['GITHUB_ENV'], 'a', encoding='utf8') as env:
    env.write(f'VERSION={version}\nIPA_NAME={name}\nOTA_SUBDIR={folder}\nINSTALL_URL={base}/install.html\n')
print(json.dumps(report, ensure_ascii=False))
