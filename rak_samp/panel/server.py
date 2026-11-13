"""Local Termuh dashboard. Python 3.10+; binds to loopback by default."""
import argparse
import configparser
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parent.parent
WEB = Path(__file__).resolve().parent
STATE = Path(os.environ.get('TERMUH_PANEL_HOME', Path(os.environ.get('LOCALAPPDATA', Path.home())) / 'TermuhPanel'))
PORT = int(os.environ.get('TERMUH_PANEL_PORT', '8765'))
DEMO = os.environ.get('TERMUH_PANEL_DEMO') == '1'
TOKEN = secrets.token_urlsafe(32)
LOCK = threading.RLock()
processes = {}
runs = {}
SERVER_RE = re.compile(r'\{id=(\d+), name="([^"]+)", host="([^"]+)", port=(\d+), mobile=(true|false)\}')

def servers():
    path = ROOT / 'servers-catalog.txt'
    if not path.exists(): path = ROOT / 'termuh-servers.lua'
    return [dict(id=int(i), name=n, host=h, port=int(p)) for i,n,h,p,m in SERVER_RE.findall(path.read_text(encoding='utf-8')) if m == 'false']

def load_profiles():
    try:
        data = json.loads((STATE / 'profiles.json').read_text(encoding='utf-8'))
        return data if isinstance(data, list) else []
    except (OSError, ValueError): return []

def save_profiles(data):
    STATE.mkdir(parents=True, exist_ok=True)
    path = STATE / 'profiles.json'
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(tmp, path)

def instance(account_id): return STATE / 'instances' / account_id

def get_account(account_id):
    return next((p for p in load_profiles() if p['id'] == account_id), None)

def cleanup(account_id):
    # Remove only credentials and transient IPC from a stopped panel-owned client.
    for filename in ('termuh/settings.txt', 'termuh/panel-command.txt', 'termuh/panel-command.tmp', 'termuh/panel-state.txt', 'termuh/panel-state.tmp'):
        (instance(account_id) / filename).unlink(missing_ok=True)

def process_running(account_id):
    p = processes.get(account_id)
    if p and p.poll() is not None:
        cleanup(account_id)
        processes.pop(account_id, None)
        runs.pop(account_id, None)
        return False
    return p is not None

def snapshot(account):
    account_id = account['id']
    running = process_running(account_id)
    result = dict(account, running=running, live=False, run_id=runs.get(account_id) if running else None)
    path = instance(account_id) / 'termuh/panel-state.txt'
    if running:
        try:
            if time.time() - path.stat().st_mtime >= 10: return result
            values = dict(line.split('=', 1) for line in path.read_text(encoding='ascii').splitlines() if '=' in line)
            if values.get('connected') not in ('true', 'false') or values.get('spawned') not in ('true', 'false'):
                raise ValueError('Incomplete state')
            numeric = {k: float(values[k]) for k in ('x','y','z','drift','health','armor','level')}
            numeric.update({k: int(values.get(k, '0')) for k in ('deaths','spawns','stats_at')})
            extra = {k: values.get(k, '') if re.fullmatch(r'[0-9.]*', values.get(k,'')) else '' for k in ('cash','bank','paydays')}
            result.update(numeric, **extra, live=True, connected=values['connected'] == 'true', spawned=values['spawned'] == 'true', settling=values.get('settling') == 'true', dead=values.get('dead') == 'true', dialog=values.get('dialog') if values.get('dialog') in ('none','auth','stats','menu','other') else 'none')
            if values['connected'] == 'true' and values.get('dialog_active') == 'true':
                def decode_field(name, limit):
                    raw = values[name]
                    if len(raw) > limit * 2 or not re.fullmatch(r'(?:[0-9a-fA-F]{2})*', raw): raise ValueError('Invalid dialog')
                    return bytes.fromhex(raw).decode('cp1251', errors='replace')
                revision, dialog_id, style = (int(values[k]) for k in ('dialog_revision','dialog_id','dialog_style'))
                if not (0 <= revision <= 2147483647 and 0 <= dialog_id <= 32767 and 0 <= style <= 5): raise ValueError('Invalid dialog')
                result['active_dialog'] = {'revision':revision,'id':dialog_id,'style':style,
                    'title':decode_field('dialog_title',255), 'text':decode_field('dialog_text',4096),
                    'button1':decode_field('dialog_button1',255), 'button2':decode_field('dialog_button2',255)}
        except (OSError, ValueError, KeyError): pass
    return result

def is_windows(): return os.name == 'nt'

def start(account, password, launcher=False):
    if type(launcher) is not bool: raise ValueError('Неверная настройка лаунчера')
    if DEMO: raise ValueError('Запуск отключён в демонстрации')
    if not is_windows(): raise ValueError('Запуск клиента доступен в Windows')
    account_id = account['id']
    if process_running(account_id): raise ValueError('Клиент уже запущен')
    if not isinstance(password, str) or not password or password != password.strip() or any(c in password for c in '\r\n\x00'):
        raise ValueError('Пароль не может быть пустым или содержать перевод строки')
    try: encoded_password = password.encode('cp1251')
    except UnicodeEncodeError: raise ValueError('Пароль должен поддерживать кодировку CP1251')
    if len(encoded_password) > 255: raise ValueError('Пароль слишком длинный')
    endpoint = next((s for s in servers() if s['name'] == account['server']), None)
    if not endpoint: raise ValueError('Сервер отсутствует в каталоге')
    target = instance(account_id)
    for directory in ('settings','scripts','termuh'): (target / directory).mkdir(parents=True, exist_ok=True)
    for name in ('RakSAMP Lite.exe','lua51.dll'): shutil.copy2(ROOT / name, target / name)
    shutil.copy2(ROOT / 'scripts/termuh.lua', target / 'scripts/termuh.lua')
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.read(ROOT / 'client-settings.example.ini', encoding='utf-8')
    cfg['Server']['nick'] = account['nick']
    cfg['Server']['ip'] = f"{endpoint['host']}:{endpoint['port']}"
    with (target / 'settings/RakSAMP Lite.ini').open('w', encoding='utf-8') as f: cfg.write(f)
    # Clear stale state before writing credentials; remove partial files on launch failure.
    (target / 'termuh/panel-state.txt').unlink(missing_ok=True)
    (target / 'termuh/panel-command.txt').unlink(missing_ok=True)
    run_id = secrets.token_hex(16)
    try:
        # The host requires plaintext settings while it is running.
        (target / 'termuh/settings.txt').write_text('[settings]\nserver='+endpoint['name']+'\npassword='+password+'\nstationary=true\npanel=true\nhttp_preconnect=true\n[dialogs]\nregistration=false\n[launcher]\nenabled='+('true' if launcher else 'false')+'\n[cef]\nenabled=false\n', encoding='cp1251')
        processes[account_id] = subprocess.Popen([str(target / 'RakSAMP Lite.exe')], cwd=target)
        runs[account_id] = run_id
    except Exception:
        cleanup(account_id)
        raise

def stop(account_id):
    p = processes.get(account_id)
    if not p: return
    if p.poll() is None:
        p.terminate()
        try: p.wait(timeout=5)
        except subprocess.TimeoutExpired: p.kill(); p.wait(timeout=5)
    processes.pop(account_id, None)
    runs.pop(account_id, None)
    cleanup(account_id)

def command(account_id, value):
    if value not in ('/stats','/mm','!anchor'): raise ValueError('Неизвестная команда')
    account = get_account(account_id)
    if not account or not process_running(account_id): raise ValueError('Клиент не запущен')
    current = snapshot(account)
    if not current.get('live') or not current.get('spawned'): raise ValueError('Персонаж ещё не в игре')
    enqueue(account_id, value)

def enqueue(account_id, value):
    path = instance(account_id) / 'termuh/panel-command.txt'
    if path.exists(): raise ValueError('Предыдущая команда ожидает отправки')
    temp = path.with_suffix('.tmp')
    try:
        temp.write_text(value+'\n', encoding='ascii')
        os.replace(temp, path)
    finally: temp.unlink(missing_ok=True)

def reply(account_id, payload):
    account = get_account(account_id)
    if not account or not process_running(account_id): raise ValueError('Клиент не запущен')
    state = snapshot(account)
    dialog = state.get('active_dialog')
    if not state.get('live') or not dialog or payload.get('run_id') != state.get('run_id'):
        raise ValueError('Диалог больше не активен; обновите его')
    if type(payload.get('revision')) is not int or type(payload.get('dialog_id')) is not int or payload['revision'] != dialog['revision'] or payload['dialog_id'] != dialog['id']:
        raise ValueError('Диалог изменился; обновите его')
    button, index, text = payload.get('button'), payload.get('list'), payload.get('input')
    if type(button) is not int or button not in (0,1) or type(index) is not int or not isinstance(text,str): raise ValueError('Некорректный ответ')
    if not dialog['button1' if button == 1 else 'button2']: raise ValueError('Кнопка недоступна')
    if '\x00' in text: raise ValueError('Некорректный ввод')
    try: data = text.encode('cp1251')
    except UnicodeEncodeError: raise ValueError('Ввод должен поддерживать CP1251')
    if len(data) > 255: raise ValueError('Ввод длиннее 255 байт')
    if dialog['style'] in (2,4,5) and button == 1:
        lines = dialog['text'].split('\n')
        if dialog['text'].endswith('\n'): lines.pop()
        if dialog['style'] == 5: lines = lines[1:]
        if not 0 <= index < len(lines): raise ValueError('Выберите строку')
    elif index != -1: raise ValueError('Некорректная строка')
    if dialog['style'] not in (1,3) and text: raise ValueError('У этого диалога нет поля ввода')
    enqueue(account_id, f"dialog|{dialog['revision']}|{dialog['id']}|{button}|{index}|{data.hex()}")

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def allowed_host(self):
        h = self.headers.get('Host','')
        return DEMO or h in (f'127.0.0.1:{PORT}', f'localhost:{PORT}')
    def response(self, code, body, typ='application/json; charset=utf-8'):
        data = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code); self.send_header('Content-Type',typ); self.send_header('Content-Length',str(len(data)))
        self.send_header('Cache-Control','no-store'); self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Content-Security-Policy',"default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'")
        self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        if not self.allowed_host(): return self.response(403, {'error':'Недопустимый адрес'})
        if self.path == '/api/state':
            if not hmac.compare_digest(self.headers.get('X-Termuh-Token',''), TOKEN): return self.response(403, {'error':'Недопустимый токен'})
            with LOCK:
                profiles = load_profiles() if not DEMO else [{'id':'demo','nick':'Alex_Smith','server':'Space'}]
                accounts = [snapshot(a) for a in profiles] if not DEMO else [dict(profiles[0],running=True,live=True,connected=True,spawned=True,x=1492.5,y=-1721.3,z=13.5,drift=0.1,health=100,armor=0,level=23,settling=False,dead=False,deaths=1,spawns=2,dialog='other',stats_at=int(time.time()),cash='12.540.000',bank='5.250.000',paydays='28',run_id='demo-run',active_dialog={'id':166,'revision':5,'style':2,'title':'Выберите действие','text':'Информация\nНастройки\nЗакрыть меню','button1':'Выбрать','button2':'Отмена'})]
                return self.response(200, {'accounts':accounts,'servers':servers(),'demo':DEMO})
        files = {'/':('index.html','text/html; charset=utf-8'), '/app.js':('app.js','text/javascript; charset=utf-8'), '/style.css':('style.css','text/css; charset=utf-8')}
        if self.path not in files: return self.response(404, {'error':'Не найдено'})
        name, typ = files[self.path]
        content = (WEB / name).read_bytes()
        if name == 'index.html': content = content.replace(b'__TOKEN__', TOKEN.encode())
        return self.response(200, content, typ)
    def do_POST(self):
        origin = self.headers.get('Origin','')
        if not self.allowed_host() or origin != 'http://' + self.headers.get('Host','') or not hmac.compare_digest(self.headers.get('X-Termuh-Token',''),TOKEN):
            return self.response(403, {'error':'Запрос отклонён'})
        if DEMO: return self.response(403, {'error':'Демонстрация: изменения отключены'})
        try:
            n = int(self.headers.get('Content-Length','0'))
            if n <= 0 or n > 4096: raise ValueError('Недопустимый размер запроса')
            if self.headers.get_content_type() != 'application/json': raise ValueError('Ожидается JSON')
            payload = json.loads(self.rfile.read(n))
            if not isinstance(payload,dict): raise ValueError('Ожидается объект')
            with LOCK:
                if self.path == '/api/accounts':
                    nick, server = payload.get('nick',''),payload.get('server','')
                    if not isinstance(nick,str) or not re.fullmatch(r'[A-Za-z0-9_]{3,24}',nick): raise ValueError('Ник: 3–24 латинских символа, цифры или _')
                    if server not in [x['name'] for x in servers()]: raise ValueError('Выберите сервер')
                    profiles = load_profiles()
                    if any(x['nick'].lower() == nick.lower() and x['server'] == server for x in profiles): raise ValueError('Аккаунт уже добавлен')
                    profiles.append({'id':uuid.uuid4().hex,'nick':nick,'server':server});save_profiles(profiles)
                else:
                    account = get_account(payload.get('id'))
                    if not account: raise ValueError('Аккаунт не найден')
                    if self.path == '/api/start': start(account, payload.get('password',''), payload.get('launcher',False))
                    elif self.path == '/api/stop': stop(account['id'])
                    elif self.path == '/api/command': command(account['id'],payload.get('command'))
                    elif self.path == '/api/reply': reply(account['id'],payload)
                    elif self.path == '/api/delete':
                        if process_running(account['id']): raise ValueError('Сначала остановите клиент')
                        save_profiles([x for x in load_profiles() if x['id'] != account['id']])
                    else: return self.response(404, {'error':'Не найдено'})
            return self.response(200, {'ok':True})
        except (ValueError, TypeError, OSError, json.JSONDecodeError) as e:
            return self.response(400, {'error':str(e)})

def main():
    host = '0.0.0.0' if DEMO else '127.0.0.1'
    server = ThreadingHTTPServer((host,PORT),Handler)
    print(f'Termuh Panel: http://127.0.0.1:{PORT}',flush=True)
    if '--open' in sys.argv and not DEMO:
        import webbrowser
        threading.Thread(target=webbrowser.open, args=(f'http://127.0.0.1:{PORT}/',), daemon=True).start()
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally:
        with LOCK:
            for account_id in list(processes): stop(account_id)
        server.server_close()
if __name__ == '__main__': main()
