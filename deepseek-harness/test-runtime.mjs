import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { once } from 'node:events'
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import http from 'node:http'
import https from 'node:https'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import vm from 'node:vm'
import { Worker } from 'node:worker_threads'

const dshRoot = process.env.DSH_TEST_ROOT ?? '/usr/local/lib/node_modules/@deepseek-ai/dsh'
const requireDsh = createRequire(join(dshRoot, 'package.json'))
const pdfPath = join(requireDsh.resolve('@deepseek-ai/dsh-client-ui-sidebar-documentpreview/package.json'), '../lib/client.pdf.js')
const pdf = await readFile(pdfPath, 'utf8')
const removeIterator = `
  const prototype = Object.getPrototypeOf(Object.getPrototypeOf([][Symbol.iterator]()));
  for (const name of ['map', 'filter', 'take', 'drop', 'flatMap', 'reduce', 'toArray', 'forEach', 'some', 'every', 'find', 'join']) delete prototype[name];
  delete globalThis.Iterator;
`
const checkIterator = `
  JSON.stringify(Iterator.from([1, 2, 3]).filter(x => x > 1).map(x => x * 2).toArray()) === '[4,6]'
    && new Map([[1, 'one']]).values().some(x => x === 'one')
`

test('PDF page initializes Iterator helpers before registering its module', () => {
  let registered = false
  const context = vm.createContext({ window: { __ModuleLoader__: { load() { registered = true } } } })
  vm.runInContext(removeIterator, context)
  vm.runInContext(pdf, context, { timeout: 5000 })
  assert.ok(registered)
  assert.equal(vm.runInContext(checkIterator, context), true)
})

test('embedded PDF worker initializes its own Iterator helpers', async t => {
  const declaration = pdf.split('\n').find(line => line.trimStart().startsWith('var _dsh_pdf_worker_default = '))
  assert.ok(declaration, 'PDF worker declaration must exist')
  const source = vm.runInNewContext(`${declaration}\n_dsh_pdf_worker_default`)
  const worker = new Worker(`
    const { parentPort, workerData } = require('node:worker_threads');
    (async () => {
      ${removeIterator}
      const pdf = await import('data:text/javascript;base64,' + Buffer.from(workerData).toString('base64'));
      parentPort.postMessage({ ok: (${checkIterator}) && typeof pdf.WorkerMessageHandler === 'function' });
    })().catch(error => { throw error });
  `, { eval: true, workerData: source })
  t.after(() => worker.terminate())
  const [result] = await once(worker, 'message')
  assert.equal(result.ok, true)
})

test('Caddy forwards valid settings requests and rejects cross-site API requests', { timeout: 60000 }, async t => {
  const caddy = process.env.CADDY_BINARY ?? 'caddy'
  const directory = await mkdtemp(join(tmpdir(), 'dsh-proxy-test-'))
  t.after(() => rm(directory, { recursive: true, force: true }))
  let forwarded = 0
  const backend = http.createServer(async (request, response) => {
    forwarded++
    let body = ''
    for await (const chunk of request) body += chunk
    response.setHeader('Content-Type', 'application/json')
    response.end(JSON.stringify({ ok: true, headers: request.headers, body: body ? JSON.parse(body) : null }))
  })
  backend.listen(0, '127.0.0.1')
  await once(backend, 'listening')
  t.after(() => new Promise(resolve => backend.close(resolve)))
  const backendPort = backend.address().port
  const reserve = http.createServer()
  reserve.listen(0, '127.0.0.1')
  await once(reserve, 'listening')
  const port = reserve.address().port
  await new Promise(resolve => reserve.close(resolve))
  const password = 'dsh-test-password'
  const hash = spawnSync(caddy, ['hash-password', '--algorithm', 'argon2id', '--plaintext', password], { encoding: 'utf8' })
  assert.equal(hash.status, 0, hash.error?.message ?? hash.stderr)
  const config = (await readFile(process.env.DSH_CADDYFILE ?? '/etc/caddy/Caddyfile', 'utf8'))
    .replaceAll(':8443', `:${port}`).replaceAll('127.0.0.1:3080', `127.0.0.1:${backendPort}`)
  const configPath = join(directory, 'Caddyfile')
  await writeFile(configPath, config)
  const processCaddy = spawn(caddy, ['run', '--config', configPath, '--adapter', 'caddyfile'], {
    env: { ...process.env, CADDY_ACCESS_HOST: '127.0.0.1', DSH_AUTH_USERNAME: 'test', DSH_AUTH_PASSWORD_HASH: hash.stdout.trim(), XDG_DATA_HOME: directory, XDG_CONFIG_HOME: directory },
    stdio: ['ignore', 'ignore', 'pipe'],
  })
  let logs = ''
  processCaddy.stderr.on('data', chunk => { logs += chunk })
  const exited = once(processCaddy, 'exit')
  t.after(async () => { processCaddy.kill('SIGTERM'); await exited })
  const origin = `https://127.0.0.1:${port}`
  const request = (pathname, headers = {}, authenticated = true) => new Promise((resolve, reject) => {
    const req = https.request(`${origin}${pathname}`, {
      method: 'POST', rejectUnauthorized: false, servername: '',
      headers: { 'Content-Type': 'application/json', Origin: origin, ...(authenticated ? { Authorization: `Basic ${Buffer.from(`test:${password}`).toString('base64')}` } : {}), ...headers },
    }, response => {
      let body = ''
      response.on('data', chunk => { body += chunk })
      response.on('end', () => resolve({ status: response.statusCode, body }))
    })
    req.setTimeout(3000, () => req.destroy(new Error('proxy request timed out')))
    req.on('error', reject)
    req.end(JSON.stringify({ value: 'test' }))
  })
  for (let attempt = 0; ; attempt++) {
    try { await request('/'); break } catch (error) {
      if (attempt === 100 || processCaddy.exitCode !== null) throw new Error(logs, { cause: error })
      await new Promise(resolve => setTimeout(resolve, 100))
    }
  }
  for (const endpoint of ['settings/describe', 'settings/update', 'settings/replace', 'settings/mutate', 'credentials/describe', 'credentials/set', 'credentials/unset', 'llm/discoverModels']) {
    const response = await request(`/api/${endpoint}`)
    assert.equal(response.status, 200, endpoint)
    const data = JSON.parse(response.body)
    assert.equal(data.ok, true)
    assert.equal(data.headers.host, `127.0.0.1:${backendPort}`)
    assert.equal(data.headers.origin, undefined)
    assert.equal(data.headers.authorization, undefined)
    assert.equal(data.body.value, 'test')
  }
  const beforeRejected = forwarded
  for (const pathname of ['/api', '/api/settings/update', '/api/credentials/set', '/api/remote.mux']) {
    for (const headers of [{ Origin: 'https://attacker.invalid' }, { Origin: 'null' }, { Origin: `http://127.0.0.1:${port}` }, { Origin: 'https://127.0.0.1:1' }, { 'Sec-Fetch-Site': 'cross-site' }, { Origin: '', 'Sec-Fetch-Site': 'cross-site' }]) {
      assert.equal((await request(pathname, headers)).status, 403)
    }
  }
  // Caddy can return an empty 200 for unmatched hosts; no request may reach DSH.
  assert.equal((await request('/api/settings/update', { Host: 'attacker.invalid', Origin: 'https://attacker.invalid' })).body, '')
  assert.equal((await request('/api/settings/describe', {}, false)).status, 401)
  assert.equal(forwarded, beforeRejected, 'rejected requests must never reach DSH')
})
