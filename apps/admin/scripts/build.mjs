// Сборка панели оператора: esbuild собирает React-приложение в dist/.
//
// Хэш в имени JS и CSS позволяет кешировать файлы навсегда; index.html
// пишется без кеша. Никаких сторонних CDN и встроенных скриптов: CSP
// панели разрешает только свой источник.

import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as esbuild from 'esbuild';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');

export async function build() {
  await rm(dist, { recursive: true, force: true });
  const result = await esbuild.build({
    absWorkingDir: root,
    entryPoints: { app: 'src/main.tsx' },
    outdir: join(dist, 'assets'),
    entryNames: '[name]-[hash]',
    assetNames: '[name]-[hash]',
    bundle: true,
    format: 'esm',
    target: ['es2022'],
    jsx: 'automatic',
    minify: true,
    sourcemap: false,
    legalComments: 'linked',
    metafile: true,
    logLevel: 'warning',
  });
  const outputs = Object.keys(result.metafile.outputs);
  const asset = (ext) => {
    const file = outputs.find(
      (f) => f.endsWith(ext) && !f.endsWith('.LEGAL.txt'),
    );
    if (!file) throw new Error(`esbuild не выдал файл ${ext}`);
    return '/' + relative(dist, join(root, file)).split('\\').join('/');
  };
  const js = asset('.js');
  const css = outputs.find((f) => f.endsWith('.css'));
  const html = `<!doctype html>
<html lang="ru">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light dark">
    <meta name="robots" content="noindex, nofollow">
    <meta name="referrer" content="no-referrer">
    <title>Backpeer — панель оператора</title>
    <link rel="icon" href="/favicon.svg" type="image/svg+xml">
    ${css ? `<link rel="stylesheet" href="/${relative(dist, join(root, css)).split('\\').join('/')}">` : ''}
    <script type="module" src="${js}"></script>
  </head>
  <body>
    <div id="root"></div>
    <noscript>Для панели нужен JavaScript.</noscript>
  </body>
</html>
`;
  await writeFile(join(dist, 'index.html'), html);
  await mkdir(join(dist, 'assets'), { recursive: true });
  await cp(join(root, 'public'), dist, { recursive: true });
  console.log(`Панель собрана: ${js}${css ? `, ${css}` : ''}`);
  return { js, css };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  build().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
