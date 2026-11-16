// Режим разработки: пересборка dist/ при изменении src/ и public/.
// Панель отдаёт бэкенд (`admin serve --config …`), поэтому отдельный
// статический сервер не поднимается: он бы не имел доступа к API.
import { watch } from 'node:fs';
import { join } from 'node:path';
import { build } from './build.mjs';

const root = join(new URL('.', import.meta.url).pathname, '..');
let timer;
let running = Promise.resolve();

const rebuild = () => {
  clearTimeout(timer);
  timer = setTimeout(() => {
    running = running
      .then(build)
      .catch((error) => console.error(`Ошибка сборки:\n${error.message}`));
  }, 100);
};

await build();
console.log('Слежу за src/ и public/. Панель обновляйте в браузере. Ctrl+C — стоп.');
for (const dir of ['src', 'public']) {
  watch(join(root, dir), { recursive: true }, rebuild);
}
