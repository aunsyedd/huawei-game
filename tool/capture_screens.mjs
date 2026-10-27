// Captures user-guide screenshots from a real build in headless Chrome.
//
//   flutter build web --release
//   python -m http.server 8766 --directory build/web
//   chrome --headless=new --remote-debugging-port=9333 --user-data-dir=<temp>
//   node tool/capture_screens.mjs http://localhost:8766 docs/screenshots
//
// Buttons are found through Flutter's accessibility tree, so clicks don't
// depend on layout coordinates.
import { mkdirSync, writeFileSync } from 'node:fs';

const [base = 'http://localhost:8766', outDir = 'docs/screenshots'] = process.argv.slice(2);
const port = 9333;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
mkdirSync(outDir, { recursive: true });

const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json();
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => (ws.onopen = r));
let id = 0;
const pending = new Map();
ws.onmessage = (m) => {
  const msg = JSON.parse(m.data);
  if (msg.id && pending.has(msg.id)) {
    pending.get(msg.id)(msg);
    pending.delete(msg.id);
  }
};
const send = (method, params = {}) =>
  new Promise((r) => {
    const i = ++id;
    pending.set(i, r);
    ws.send(JSON.stringify({ id: i, method, params }));
  });
const evalJs = async (expr) =>
  (await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true })).result?.result?.value;

async function shot(name) {
  const r = await send('Page.captureScreenshot', { format: 'png' });
  writeFileSync(`${outDir}/${name}.png`, Buffer.from(r.result.data, 'base64'));
  console.log('saved', name);
}

async function mouse(x, y, holdMs = 60) {
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', buttons: 1, clickCount: 1 });
  await sleep(holdMs);
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', buttons: 0, clickCount: 1 });
}

async function enableSemantics() {
  await evalJs(`(() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.click(); return !!p; })()`);
  await sleep(400);
}

/** Centre of the first accessibility node whose label contains `text`. */
async function find(text) {
  return evalJs(`(() => {
    const t = ${JSON.stringify(text)}.toLowerCase();
    const nodes = [...document.querySelectorAll('flt-semantics, flt-semantics *')];
    for (const n of nodes) {
      const label = ((n.getAttribute('aria-label') || '') + ' ' + (n.textContent || '')).toLowerCase();
      if (!label.includes(t)) continue;
      const r = n.getBoundingClientRect();
      if (r.width < 4 || r.height < 4 || r.width > 700) continue;
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    }
    return null;
  })()`);
}

async function clickText(text, tries = 20) {
  for (let i = 0; i < tries; i++) {
    await enableSemantics();
    const p = await find(text);
    if (p) {
      await mouse(p.x, p.y);
      return true;
    }
    await sleep(500);
  }
  console.log('not found:', text);
  return false;
}

async function key(code, keyName, holdMs) {
  await send('Input.dispatchKeyEvent', { type: 'keyDown', code, key: keyName, windowsVirtualKeyCode: keyName.toUpperCase().charCodeAt(0) });
  await sleep(holdMs);
  await send('Input.dispatchKeyEvent', { type: 'keyUp', code, key: keyName, windowsVirtualKeyCode: keyName.toUpperCase().charCodeAt(0) });
}

await send('Page.enable');
await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 812, height: 375, deviceScaleFactor: 2, mobile: false });

// Fresh start: story on first launch.
await send('Page.navigate', { url: base + '/#/' });
await sleep(7000);
await shot('01_story');
await clickText('next');
await clickText('next');
await sleep(500);
await shot('02_story_trees');
for (let i = 0; i < 4; i++) {
  await enableSemantics();
  if (await find("let's go")) break;
  await clickText('next', 4);
  await sleep(400);
}
await clickText("let's go");
await sleep(2500);
await shot('03_menu');
await clickText('locker');
await sleep(800);
await shot('04_locker');
await clickText('close');
await evalJs("location.hash = '#/guide'");
await sleep(1500);
await shot('05_how_to_play');
await evalJs("location.hash = '#/settings'");
await sleep(1500);
await shot('06_settings');
await evalJs("location.hash = '#/leaderboard'");
await sleep(1500);
await shot('07_leaderboard');
await evalJs("location.hash = '#/lobby'");
await sleep(1500);
await shot('08_lobby');
await sleep(2500); // lobby fills and starts the match
await sleep(1000);
await shot('09_landing_map');
await clickText('drop now');
await sleep(2500);
await shot('10_match_tutorial');
// Walk, aim and fire.
await key('KeyD', 'd', 700);
await mouse(600, 150, 1500);
await sleep(300);
await shot('11_match_action');
// Fight until the match ends for the player.
let done = false;
for (let i = 0; i < 40 && !done; i++) {
  await mouse(300 + ((i * 97) % 300), 100 + ((i * 53) % 150), 1500);
  await key(['KeyW', 'KeyA', 'KeyS', 'KeyD'][i % 4], ['w', 'a', 's', 'd'][i % 4], 600);
  await enableSemantics();
  done = !!(await find('see results'));
  if (i === 12) await shot('12_match_later');
}
if (done) {
  await shot('13_tagged_out');
  await clickText('see results');
  await sleep(2500);
  await shot('14_results');
} else {
  console.log('match did not finish in time');
}
ws.close();
process.exit(0);
