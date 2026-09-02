// AgentBridge raw-TCP helper for Windows (no /dev/tcp).
// Usage: node term.js '<uboot command line>'
// Sends the command with \r, reads until __MARK_END__ appears on its own line (or timeout).
const net = require('net');

const cmd = process.argv[2] || '';
const HOST = '127.0.0.1';
const PORT = 2000;

const client = net.createConnection({ host: HOST, port: PORT }, () => {
  setTimeout(() => {
    client.write('echo __MARK_BEGIN__; ' + cmd + '; echo __MARK_END__\r');
  }, 300);
});

let out = '';
let done = false;
const finish = (code) => { if (done) return; done = true; client.destroy(); process.exit(code); };

client.on('data', (chunk) => {
  out += chunk.toString('utf-8');
  // marker must appear on its own line (echo of the command line contains "echo __MARK_END__")
  if (/\n__MARK_END__/.test(out) || /\r__MARK_END__/.test(out)) {
    process.stdout.write(out);
    finish(0);
  }
});

client.on('error', (err) => { console.error('[error]', err.message); finish(1); });
client.on('close', () => { if (!done) { process.stdout.write(out); finish(0); } });

setTimeout(() => { process.stdout.write(out); finish(0); }, 15000);
