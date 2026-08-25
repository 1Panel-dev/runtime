import { readFile, writeFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'

const dshRoot = resolve(process.argv[2] ?? '/usr/local/lib/node_modules/@deepseek-ai/dsh')
const requireFromDsh = createRequire(join(dshRoot, 'package.json'))
const flag = 'globalThis.__DSH_AUTHENTICATED_SETTINGS__ === true'

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

const settingsPath = join(
  await packageRoot('@deepseek-ai/dsh-client-ui-settings'),
  'lib/client.js',
)
let settings = await readFile(settingsPath, 'utf8')
settings = replaceOnce(
  settings,
  'new SettingsScopeController(connection.api, spec, this.mirror, connection.isLoopback ? "host" : "memory", this.schema)',
  `new SettingsScopeController(connection.api, spec, this.mirror, connection.isLoopback || ${flag} ? "host" : "memory", this.schema)`,
  'settings scope',
)
settings = replaceOnce(
  settings,
  'new SettingsDescribeMirror(connection.api, connection.isLoopback ? "host" : "memory")',
  `new SettingsDescribeMirror(connection.api, connection.isLoopback || ${flag} ? "host" : "memory")`,
  'settings mirror',
)
await writeFile(settingsPath, settings, 'utf8')

const frontendPath = join(
  await packageRoot('@deepseek-ai/dsh-web-frontend'),
  'dist/index.html',
)
let frontend = await readFile(frontendPath, 'utf8')
const bootstrap = '<script src="/dsh-deployment.js"></script>'
const moduleScripts = frontend.match(/  <script type="module"[^>]*><\/script>/gu) ?? []
if (moduleScripts.length !== 1 || frontend.includes(bootstrap)) {
  throw new Error(`unexpected frontend source shape: module=${moduleScripts.length}`)
}
frontend = frontend.replace(moduleScripts[0], `  ${bootstrap}\n${moduleScripts[0]}`)
await writeFile(frontendPath, frontend, 'utf8')

if ((settings.split(flag).length - 1) !== 2 || !frontend.includes(`${bootstrap}\n${moduleScripts[0]}`)) {
  throw new Error('authenticated settings patch verification failed')
}
