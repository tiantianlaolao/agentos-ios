import pathlib,plistlib,re,sys,zipfile
project=pathlib.Path('project.yml').read_text()
version=re.search(r'MARKETING_VERSION:\s*"?([\d.]+)',project).group(1)
build=re.search(r'CURRENT_PROJECT_VERSION:\s*"?(\d+)',project).group(1)
with zipfile.ZipFile(sys.argv[1]) as ipa:
 names=[n for n in ipa.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist',n)]
 assert len(names)==1
 info=plistlib.loads(ipa.read(names[0]))
 assert info['CFBundleShortVersionString']==version,(info.get('CFBundleShortVersionString'),version)
 assert info['CFBundleVersion']==build,(info.get('CFBundleVersion'),build)
 assert info['CFBundleIdentifier']=='com.agentosplus.app'
print(f'Validated App Store IPA: {version} ({build})')
