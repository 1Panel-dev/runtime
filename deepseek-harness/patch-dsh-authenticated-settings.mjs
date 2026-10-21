import { readFile, writeFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { runInNewContext } from 'node:vm'

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
  return source.replace(original, () => replacement)
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

const compatRoot = resolve(process.argv[3] ?? '/tmp/dsh-browser-compat')
const requireCompat = createRequire(join(compatRoot, 'package.json'))
const { build, transform } = requireCompat('esbuild')
const { outputFiles } = await build({
  entryPoints: [requireCompat.resolve('core-js/actual/iterator')],
  bundle: true,
  format: 'iife',
  target: 'es2022',
  minify: true,
  write: false,
  banner: { js: `/*!\n${await readFile(requireCompat.resolve('core-js/LICENSE'), 'utf8')}\n*/` },
})
const polyfill = outputFiles[0].text
const pdfPath = join(await packageRoot('@deepseek-ai/dsh-client-ui-sidebar-documentpreview'), 'lib/client.pdf.js')
let pdf = await readFile(pdfPath, 'utf8')
// Preserve PDF.js license notices through esbuild's comment filtering.
pdf = pdf.replaceAll('@licstart', '@license @licstart')
const workerDeclaration = 'var _dsh_pdf_worker_default = '
const workerLines = pdf.split('\n').filter(line => line.trimStart().startsWith(workerDeclaration))
if (workerLines.length !== 1) throw new Error('unexpected PDF worker source shape')
const workerSource = runInNewContext(workerLines[0].trim().slice(workerDeclaration.length, -1), {}, { timeout: 1000 })
if (typeof workerSource !== 'string') throw new Error('unexpected PDF worker source value')
// A Blob worker has its own globals; the page's polyfills cannot reach it.
const worker = await transform(`${polyfill}\n${workerSource}`, { target: 'es2022', format: 'esm', minify: true })
pdf = replaceOnce(pdf, workerLines[0], `${workerDeclaration}${JSON.stringify(worker.code)};`, 'PDF worker compatibility')
const browser = await transform(`${polyfill}\n${pdf}`, { target: 'es2022' })
await writeFile(pdfPath, browser.code, 'utf8')
