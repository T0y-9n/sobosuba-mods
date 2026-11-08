from pathlib import Path
import json, urllib.request, hashlib, subprocess, sys
qa=Path(sys.argv[1]).resolve()
qa.mkdir(parents=True, exist_ok=False)
repo=Path(__file__).resolve().parents[2]
catalog=json.loads((repo/'catalog.json').read_text(encoding='utf-8'))
catalog['mods'][0]['variants']=[dict(version='1.3.11-1.0.0',game_versions=['1.3.11'],zip='https://github.com/T0y-9n/sobosuba-mods/releases/download/1.3.11-1.0.0/sobosuba-prime-balls-1.3.11-1.0.0.zip',sha256='8c1a9925472d8a1c9c089f7af65b1fe6848c9227bafc98d0a7361e0dce12d35e')]
(qa/'catalog.json').write_text(json.dumps(catalog,indent=2),encoding='utf-8')
(qa/'empty-catalog.json').write_text('{"mods":[]}',encoding='utf-8')
(qa/'game').mkdir(exist_ok=True)
(qa/'game/sobosuba.exe').write_bytes(b'')
(qa/'user-data').mkdir(exist_ok=True)
results=[]
for version,entry in [('1.2.3',catalog['mods'][0]),('1.3.11',catalog['mods'][0]['variants'][0])]:
    zip_path=qa/('prime-'+version+'.zip')
    if not zip_path.exists(): urllib.request.urlretrieve(entry['zip'],zip_path)
    assert hashlib.sha256(zip_path.read_bytes()).hexdigest()==entry['sha256']
    request=dict(action='install',game_folder=str(qa/'game'),user_data=str(qa/'user-data'),game_version=version,zip=str(zip_path),sha256=entry['sha256'])
    request_path=qa/('install-'+version+'.json')
    request_path.write_text(json.dumps(request),encoding='utf-8')
    run=subprocess.run(['powershell.exe','-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(repo/'manager/backend.ps1'),'-RequestPath',str(request_path)],capture_output=True,text=True,timeout=40,creationflags=subprocess.CREATE_NO_WINDOW)
    result=json.loads(run.stdout)
    assert result['ok'],result
    results.append(result)
    if version=='1.2.3':
        request.update(action='disable',id='prime_sobo',layout='game-autoload')
        request_path.write_text(json.dumps(request),encoding='utf-8')
        run=subprocess.run(['powershell.exe','-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(repo/'manager/backend.ps1'),'-RequestPath',str(request_path)],capture_output=True,text=True,timeout=40,creationflags=subprocess.CREATE_NO_WINDOW)
        result=json.loads(run.stdout)
        assert result['ok'],result
assert (qa/'game/mods/prime_sobo/prime_sobo.gd').is_file()
assert (qa/'user-data/prime_mod/prime_sobo.gd').is_file()
assert (qa/'user-data/styles/prime_bootstrap.tres').is_file()
assert (qa/'game/.sobo-mod-manager/receipts/prime_sobo.json').is_file()
assert (qa/'user-data/.sobo-mod-manager/receipts/prime_sobo.json').is_file()
(qa/'install-results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
print('Actual release ZIPs installed into separate game and user roots; both receipts retained.')
