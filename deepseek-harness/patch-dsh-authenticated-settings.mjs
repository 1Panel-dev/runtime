import { readFile, writeFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'

const dshRoot = resolve(process.argv[2] ?? '/usr/local/lib/node_modules/@deepseek-ai/dsh')
const requireFromDsh = createRequire(join(dshRoot, 'package.json'))
const proxyAuthFlag = 'process.env.ONEPANEL_DSH_AUTH_PROXY === "1"'

async function packageRoot(name) {
  const manifestPath = requireFromDsh.resolve(`${name}/package.json`)
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'))
  if (manifest.name !== name) throw new Error(`unexpected package at ${manifestPath}`)
  return dirname(manifestPath)
}

function replaceOnce(source, original, replacement, label) {
  const count = source.split(original).length - 1
  if (count !== 1 || source.includes(replacement)) {
    throw new Error(`unexpected ${label} source shape: original=${count}`)
  }
  return source.replace(original, replacement)
}

// DSH 0.2.1 persists settings through remote.settings for authenticated clients.
// Only adapt browser authentication for the loopback backend protected by Caddy.
const connectionPath = join(
  await packageRoot('@deepseek-ai/dsh-client-connection'),
  'lib/index.js',
)
let connection = await readFile(connectionPath, 'utf8')
connection = replaceOnce(
  connection,
  'isAuthenticated(request, secure = false) {\n\t\treturn this.authenticate(request, secure)?.version === COOKIE_PAYLOAD_VERSION;',
  `isAuthenticated(request, secure = false) {\n\t\tif (${proxyAuthFlag}) return true;\n\t\treturn this.authenticate(request, secure)?.version === COOKIE_PAYLOAD_VERSION;`,
  'browser proxy authentication',
)
await writeFile(connectionPath, connection, 'utf8')

if ((connection.split(proxyAuthFlag).length - 1) !== 1) {
  throw new Error('browser proxy authentication patch verification failed')
}
