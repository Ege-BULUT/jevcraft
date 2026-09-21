// Local stand-in for the decision service: answers POST /decide with a simple
// heuristic and logs every request. Usage: node agent/stub.mjs [port]
import http from 'node:http';

const PORT = Number(process.argv[2] || process.env.PORT || 8787);
let lastFailed = null; // skill id that failed last time; skipped once

function choose({ state = '', options = [] }) {
  const m = /Last: (\S+) FAILED/.exec(state);
  lastFailed = m ? m[1] : null;
  const feasible = options.filter((o) => !/^not possible/i.test(o.detail || ''));
  const pick = feasible.find((o) => o.id !== lastFailed) || feasible[0] || options[0];
  return pick && pick.id;
}

http
  .createServer((req, res) => {
    if (req.method !== 'POST' || req.url !== '/decide') {
      res.writeHead(404).end();
      return;
    }
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      let data;
      try {
        data = JSON.parse(body);
      } catch {
        res.writeHead(400, { 'content-type': 'application/json' }).end('{"error":"bad json"}');
        return;
      }
      const action = choose(data);
      const t = new Date().toISOString().slice(11, 19);
      console.log(`\n[${t}] STATE\n${data.state}`);
      for (const o of data.options || []) console.log(`  ${o.id === action ? '>' : ' '} ${o.id}: ${o.label} | ${o.detail}`);
      console.log(`[${t}] -> ${action}`);
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify(action ? { action } : { wait: true, retryMs: 3000 }));
    });
  })
  .listen(PORT, '127.0.0.1', () => console.log(`decision stub on http://127.0.0.1:${PORT}/decide`));
