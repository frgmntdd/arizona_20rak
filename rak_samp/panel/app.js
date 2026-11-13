const token = document.querySelector('meta[name="termuh-token"]').content;
const $ = selector => document.querySelector(selector);
let accountId = null, accounts = [], loadedServers = false, timer, filter = 'all', previousMarkup = '', openedDialog = null;
const escapeText = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const online = a => a.live && a.connected;
const attention = a => a.running && (!a.live || a.dead || (a.spawned && !a.settling && a.drift > 1));
function notify(text) { const node = $('#toast'); node.textContent = text; node.classList.add('show'); clearTimeout(timer); timer = setTimeout(() => node.classList.remove('show'), 4000); }
async function api(path, payload) {
  const options = {headers:{'X-Termuh-Token':token}};
  if (payload) {options.method = 'POST'; options.headers['Content-Type'] = 'application/json'; options.body = JSON.stringify(payload);}
  const response = await fetch(path,options); const data = await response.json();
  if (!response.ok) throw new Error(data.error || 'Ошибка запроса'); return data;
}
function card(a) {
  const on = online(a), warning = a.spawned && !a.settling && a.drift > 1;
  const status = on ? (a.dead ? 'Ожидание спавна' : a.spawned ? 'В игре' : 'Подключён') : a.running ? (a.live ? 'Нет подключения' : 'Нет данных') : 'Остановлен';
  const pos = a.spawned ? [a.x,a.y,a.z].map(n => Number(n).toFixed(1)).join(' / ') : '—';
  const position = a.spawned ? (a.settling ? 'Стабилизация' : warning ? `↗ ${Number(a.drift).toFixed(1)} м` : 'На месте') : '—';
  const dialog = ({auth:'Авторизация',stats:'Статистика',menu:'Игровое меню',other:'Другое окно',none:'—'})[a.dialog] || '—';
  const stats = a.stats_at ? `Обновлено в ${new Date(a.stats_at * 1000).toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})}` : 'Ещё не получена';
  const canCommand = a.live && a.spawned;
  return `<article class="card ${warning?'card-warning':''}"><div class="card-head"><div class="identity"><div class="account-avatar">${escapeText(a.nick.slice(0,1).toUpperCase())}</div><div><h3>${escapeText(a.nick)}</h3><p>Arizona RP <span class="separator">/</span> ${escapeText(a.server)}</p></div></div><span class="badge ${on&&!a.dead?'online':''} ${a.dead||warning?'warning':''}">${status}</span></div><div class="card-stats"><div><small>УРОВЕНЬ</small><strong>${a.spawned ? escapeText(a.level) : '—'}</strong></div><div><small>ПОЗИЦИЯ</small><strong>${position}</strong></div><div><small>ЗДОРОВЬЕ</small><strong>${a.spawned ? escapeText(a.health) : '—'}</strong></div></div><div class="card-details"><p class="coordinates">Координаты <span>${escapeText(pos)}</span></p><p class="coordinates">Смертей / спавнов за сессию <span>${a.live ? `${escapeText(a.deaths || 0)} / ${escapeText(a.spawns || 0)}` : '—'}</span></p><p class="coordinates">Последнее окно <span>${a.live ? escapeText(dialog) : '—'}</span></p><p class="coordinates">Банк / наличные <span>${escapeText(a.bank || '—')} / ${escapeText(a.cash || '—')}</span></p><p class="coordinates">X4 PayDay <span>${escapeText(a.paydays || '—')}</span></p></div><div class="stats-note">${escapeText(stats)} <span>· /stats</span></div><div class="card-actions">${a.active_dialog ? `<button class="dialog-button" data-action="dialog" data-id="${a.id}">◉ Открыть диалог</button>` : ''}${a.running ? `<button class="secondary" data-action="command" data-value="/stats" data-id="${a.id}" ${canCommand?'':'disabled'}>Статистика</button><button class="secondary" data-action="command" data-value="/mm" data-id="${a.id}" ${canCommand?'':'disabled'}>Меню</button><button class="secondary" data-action="command" data-value="!anchor" data-id="${a.id}" ${canCommand?'':'disabled'} title="Измерять смещение от текущей точки">Отметить точку</button><button class="secondary danger" data-action="stop" data-id="${a.id}">Остановить</button>` : `<button class="primary" data-action="start" data-id="${a.id}">▶ Запустить</button><button class="secondary danger" data-action="delete" data-id="${a.id}">Удалить</button>`}</div></article>`;
}
function renderCards() {
  const query = $('#account-search').value.trim().toLowerCase();
  const visible = accounts.filter(a => (!query || `${a.nick} ${a.server}`.toLowerCase().includes(query)) && (filter === 'all' || (filter === 'online' ? online(a) : attention(a))));
  const html = visible.map(card).join('');
  if (html !== previousMarkup) {
    const active = document.activeElement;
    const id = active?.dataset?.id, action = active?.dataset?.action, value = active?.dataset?.value;
    $('#cards').innerHTML = html; previousMarkup = html;
    if (id && action) [...$('#cards').querySelectorAll('button')].find(b => b.dataset.id === id && b.dataset.action === action && b.dataset.value === value)?.focus();
  }
  $('#empty').hidden = accounts.length > 0;
  $('#no-matches').hidden = accounts.length === 0 || visible.length > 0;
  const warnings = accounts.filter(attention).length;
  $('#alerts').hidden = warnings === 0;
  $('#alerts').textContent = warnings ? `◌  Требуют внимания: ${warnings}. Проверь подключение или положение персонажа.` : '';
  if (openedDialog && $('#native-dialog-modal').open) {
    const current = accounts.find(a => a.id === openedDialog.accountId);
    const d = current?.active_dialog;
    if (!current?.live || current.run_id !== openedDialog.runId || !d || d.id !== openedDialog.dialog.id || d.revision !== openedDialog.dialog.revision) {
      $('#native-warning').textContent = 'Окно изменилось или клиент отключён. Откройте актуальный диалог заново.';
      $('#native-button1').disabled = true; $('#native-button2').disabled = true;
      $('#native-input').value = '';
    }
  }
}
async function refresh(){
 try {
  const data=await api('/api/state'); accounts=data.accounts; $('#connection').textContent=data.demo?'Демонстрация':'Панель подключена';
  if(!loadedServers){$('#server').innerHTML=data.servers.map(s=>`<option value="${escapeText(s.name)}">${escapeText(s.name)}</option>`).join('');const space=[...$('#server').options].find(o=>o.value==='Space');if(space)space.selected=true;loadedServers=true;}
  $('#metric-total').textContent=accounts.length;$('#metric-online').textContent=accounts.filter(online).length;$('#metric-drift').textContent=accounts.filter(a=>a.spawned&&!a.settling&&a.drift>1).length;$('#account-count').textContent=accounts.length;
  renderCards();
 }catch(e){$('#connection').textContent='Нет связи с панелью';}
}
function cleanColors(value) { return String(value || '').replace(/\{[0-9a-fA-F]{6}\}/g, ''); }
function openNativeDialog(account) {
  const d = account.active_dialog; if (!d || !account.run_id) return;
  openedDialog = {accountId:account.id,runId:account.run_id,dialog:d};
  $('#native-account').textContent = account.nick + ' · ' + account.server;
  $('#native-title').textContent = cleanColors(d.title) || 'Диалог';
  $('#native-meta').textContent = `Окно №${d.id} · тип ${d.style}`;
  $('#native-body').textContent = cleanColors(d.text);
  const list = [2,4,5].includes(d.style);
  const input = [1,3].includes(d.style);
  $('#native-list-label').hidden = !list; $('#native-input-label').hidden = !input;
  $('#native-input').value = ''; $('#native-input').type = d.style === 3 ? 'password' : 'text';
  let lines = d.text.split('\n'); if (d.text.endsWith('\n')) lines.pop(); if (d.style === 5) lines.shift();
  $('#native-list').replaceChildren(...lines.map((line, index) => {const option=document.createElement('option');option.value=String(index);option.textContent=cleanColors(line.replace(/\r$/, '')) || '—';return option;}));
  for (const n of [1,2]) {const b=$('#native-button'+n); b.textContent=cleanColors(d['button'+n]);b.hidden=!d['button'+n];b.disabled=false;}
  $('#native-warning').textContent = 'Ответ отправляется только для этого окна. Если сервер покажет новое окно, откройте его заново.';
  $('#native-dialog-modal').showModal();
}
async function replyNative(button) {
  if (!openedDialog) return;
  const {accountId:id, runId:run_id, dialog:d}=openedDialog;
  const list = button === 1 && [2,4,5].includes(d.style) ? Number($('#native-list').value) : -1;
  const input = button === 1 && [1,3].includes(d.style) ? $('#native-input').value : '';
  $('#native-button1').disabled=true; $('#native-button2').disabled=true;
  try {
    await api('/api/reply',{id,run_id,revision:d.revision,dialog_id:d.id,button,list,input});
    $('#native-dialog-modal').close(); notify('Ответ в очереди клиента'); await refresh();
  } catch(error) {
    $('#native-warning').textContent=error.message;
    const current=accounts.find(a=>a.id===id);
    if(current?.run_id===run_id && current.active_dialog?.id===d.id && current.active_dialog?.revision===d.revision){$('#native-button1').disabled=false;$('#native-button2').disabled=false;}
  }
  finally { $('#native-input').value=''; }
}
$('#native-button1').addEventListener('click',()=>replyNative(1));
$('#native-button2').addEventListener('click',()=>replyNative(0));
$('#native-dialog-modal').addEventListener('close',()=>{openedDialog=null;$('#native-input').value='';});
['#open-add','#open-add-secondary','#open-add-empty'].forEach(id=>$(id).addEventListener('click',()=>$('#profile-modal').showModal()));
document.querySelectorAll('[data-close]').forEach(x=>x.addEventListener('click',()=>document.getElementById(x.dataset.close).close()));
$('#account-search').addEventListener('input',renderCards);
document.querySelectorAll('[data-filter]').forEach(button=>button.addEventListener('click',()=>{filter=button.dataset.filter;document.querySelectorAll('[data-filter]').forEach(b=>b.classList.toggle('active',b===button));renderCards();}));
$('#profile-form').addEventListener('submit',async e=>{e.preventDefault();try{await api('/api/accounts',{nick:$('#nick').value.trim(),server:$('#server').value});$('#profile-modal').close();e.target.reset();await refresh();notify('Профиль добавлен');}catch(error){notify(error.message)}});
$('#start-form').addEventListener('submit',async e=>{e.preventDefault();try{await api('/api/start',{id:accountId,password:$('#password').value,launcher:$('#launcher-enabled').checked});$('#start-modal').close();notify('Клиент запускается');await refresh();}catch(error){notify(error.message)}finally{$('#password').value=''}});
$('#cards').addEventListener('click',async e=>{const b=e.target.closest('button[data-action]');if(!b)return;const a=accounts.find(x=>x.id===b.dataset.id);if(!a)return;if(b.dataset.action==='dialog'){openNativeDialog(a);return;}if(b.dataset.action==='start'){accountId=a.id;$('#start-account').textContent=`${a.nick} · ${a.server}`;$('#start-modal').showModal();return;}if(b.dataset.action==='delete'&&!confirm(`Удалить профиль ${a.nick}?`))return;try{await api('/api/'+b.dataset.action,{id:a.id,command:b.dataset.value});notify(b.dataset.action==='command'?'Команда в очереди клиента':'Готово');await refresh()}catch(error){notify(error.message)}});
refresh();setInterval(refresh,3000);
