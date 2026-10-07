"""Run on existing OTA server after uploading and validating a signed build."""
import fcntl,hashlib,html,json,os,pathlib,re,shutil,sys
root=pathlib.Path('/var/www/test-install').resolve()
folder=sys.argv[1]
assert re.fullmatch(r'(production-creation|test)-[0-9]+-[0-9]+-[0-9]+',folder)
with (root/'.publish.lock').open('a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 target=root/folder;report=json.loads((target/'verification.json').read_text())
 channel=report['backend'];assert channel in ('production-creation','test')
 assert folder.startswith(channel+'-'+report['build']+'-')
 ipa=target/('AgentOS-'+channel+'-'+report['build']+'.ipa')
 assert hashlib.sha256(ipa.read_bytes()).hexdigest()==report['sha256']
 current=root/channel
 if current.exists():
  assert current.is_symlink(),'Channel exists but is not a managed symlink'
  previous=json.loads((current/'verification.json').read_text())
  assert int(report['build'])>=int(previous['build']),'Refuse older concurrent build'
 temp=root/('.'+channel+'.next');temp.unlink(missing_ok=True);temp.symlink_to(folder);temp.replace(current)
 cards=[]
 for backend,label in [('production-creation','生产创作版 · 积分购买关闭'),('test','测试购买版 · 不连接生产 coder')]:
  if (root/backend/'verification.json').exists():
   r=json.loads((root/backend/'verification.json').read_text())
   cards.append(f'<a href="{backend}/install.html">{label}<small>版本 {html.escape(r["version"])} · 构建 {html.escape(r["build"])}</small></a>')
 page='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AIHEY 安装</title><style>body{font:17px -apple-system,sans-serif;max-width:500px;margin:50px auto;padding:24px;line-height:1.7}a{display:block;margin:18px 0;padding:20px;background:#1769dc;color:white;border-radius:14px;text-decoration:none}small{display:block}</style><h1>AIHEY 安装</h1><p>此地址固定更新。请选择需要验证的环境。</p>'+''.join(cards)+'<p>请在已登记的 iPhone 上用 Safari 打开。两版会互相替换，切换后请核对账号。</p></html>'
 stage=root/'.install.next.html';stage.write_text(page,encoding='utf8');stage.replace(root/'install.html')
 removed=[]
 for backend in ('production-creation','test'):
  candidates=[]
  for p in root.iterdir():
   match=re.fullmatch(re.escape(backend)+r'-(\d+)-(\d+)-(\d+)',p.name)
   if not match or p.is_symlink() or not p.is_dir():continue
   # Only directories produced by this project's existing signed-IPA workflow.
   expected=p/('AgentOS-'+backend+'-'+match[1]+'.ipa')
   if expected.is_file() and (p/'manifest.plist').is_file() and (p/'install.html').is_file():candidates.append((int(match[1]),p))
  candidates.sort(key=lambda t:t[0],reverse=True)
  live=(root/backend).resolve() if (root/backend).exists() else None
  for _,p in candidates[2:]:
   resolved=p.resolve();assert resolved.parent==root and resolved!=live
   shutil.rmtree(resolved);removed.append(p.name)
 print(json.dumps({'fixedInstallUrl':'https://agentos.tybbtech.com:3201/test-install/install.html','channel':channel,'build':report['build'],'removed':removed}))
