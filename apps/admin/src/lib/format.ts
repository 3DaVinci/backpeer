const BYTE_UNITS = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ', 'ПБ'];

export function formatBytes(value: number | null | undefined): string {
  if (value === null || value === undefined) return '—';
  if (!Number.isFinite(value)) return '—';
  let size = Math.abs(value);
  let unit = 0;
  while (size >= 1000 && unit < BYTE_UNITS.length - 1) {
    size /= 1000;
    unit += 1;
  }
  const sign = value < 0 ? '−' : '';
  const digits = unit === 0 ? 0 : size >= 100 ? 0 : size >= 10 ? 1 : 2;
  return `${sign}${size.toFixed(digits)} ${BYTE_UNITS[unit]}`;
}

export function formatNumber(value: number | null | undefined): string {
  if (value === null || value === undefined) return '—';
  return new Intl.NumberFormat('ru-RU').format(value);
}

export function formatCredits(micro: number | null | undefined): string {
  if (micro === null || micro === undefined) return '—';
  const credits = micro / 1_000_000;
  const digits = Math.abs(credits) >= 1000 ? 0 : Math.abs(credits) >= 10 ? 1 : 2;
  return `${new Intl.NumberFormat('ru-RU', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(credits)} CR`;
}

export function formatPercent(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) {
    return '—';
  }
  return `${(value * 100).toFixed(value >= 0.995 || value === 0 ? 0 : 1)} %`;
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return new Intl.DateTimeFormat('ru-RU', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  }).format(date);
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return new Intl.DateTimeFormat('ru-RU', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
}

export function formatAgo(value: string | null | undefined): string {
  if (!value) return 'никогда';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  const seconds = Math.round((Date.now() - date.getTime()) / 1000);
  if (seconds < 0) return 'в будущем';
  if (seconds < 60) return 'только что';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} мин назад`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} ч назад`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days} дн назад`;
  return formatDate(value);
}

export function formatDuration(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return '—';
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (days > 0) return `${days} д ${hours} ч`;
  if (hours > 0) return `${hours} ч ${minutes} мин`;
  if (minutes > 0) return `${minutes} мин`;
  return `${Math.round(seconds)} с`;
}

export function shortId(value: string | null | undefined, head = 10): string {
  if (!value) return '—';
  if (value.length <= head + 6) return value;
  return `${value.slice(0, head)}…${value.slice(-4)}`;
}

export function plural(
  count: number,
  one: string,
  few: string,
  many: string,
): string {
  const n = Math.abs(count) % 100;
  const n1 = n % 10;
  if (n > 10 && n < 20) return many;
  if (n1 > 1 && n1 < 5) return few;
  if (n1 === 1) return one;
  return many;
}

export function statusLabel(status: string): string {
  switch (status) {
    case 'online':
      return 'в сети';
    case 'offline':
      return 'не в сети';
    case 'lost':
      return 'потерян';
    case 'excluded':
      return 'исключён';
    case 'leaving':
      return 'выходит';
    case 'removed':
      return 'удалён';
    case 'pending':
      return 'размещается';
    case 'ok':
      return 'здоров';
    case 'repair':
      return 'ремонт';
    case 'running':
      return 'выполняется';
    case 'verifying':
      return 'проверка';
    case 'done':
      return 'готово';
    case 'failed':
      return 'провал';
    default:
      return status;
  }
}

export function methodLabel(method: string): string {
  switch (method) {
    case 'direct':
      return 'TCP напрямую';
    case 'udp':
      return 'UDP';
    case 'relay':
      return 'relay';
    default:
      return method;
  }
}

export function ledgerKind(kind: string): string {
  switch (kind) {
    case 'starter':
      return 'стартовый грант';
    case 'storage_charge':
      return 'хранение';
    case 'storage_credit':
      return 'хранение (начисление)';
    case 'penalty':
      return 'штраф';
    case 'adjustment':
      return 'корректировка';
    default:
      return kind;
  }
}

export function countryName(code: string | null | undefined): string {
  if (!code) return '—';
  try {
    return (
      new Intl.DisplayNames(['ru'], { type: 'region' }).of(code) ?? code
    );
  } catch {
    return code;
  }
}
