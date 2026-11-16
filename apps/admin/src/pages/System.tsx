import { useFetch } from '../api';
import { Icon } from '../components/Icon';
import {
  Card,
  Empty,
  ErrorBox,
  KeyValue,
  Loading,
  StatCard,
} from '../components/ui';
import {
  formatDateTime,
  formatDuration,
  formatNumber,
} from '../lib/format';
import { useTitle } from '../lib/router';
import type { SystemInfo } from '../types';

export function System() {
  useTitle('Система');
  const { data, loading, error, reload } = useFetch<SystemInfo>('/api/system');
  return (
    <div className="page">
      <header className="page-head">
        <div>
          <h1>Система</h1>
          <p className="muted">
            Подключение к базе, схема, права и настройки панели. Только
            чтение — запись невозможна по правам роли.
          </p>
        </div>
        <button type="button" className="button" onClick={reload}>
          <Icon name="refresh" size={16} /> Обновить
        </button>
      </header>
      {loading && !data && <Loading />}
      {error && <ErrorBox message={error} onRetry={reload} />}
      {data && <Body data={data} />}
    </div>
  );
}

function Body({ data }: { data: SystemInfo }) {
  const db = data.database;
  const counts = data.counts;
  const service = data.service;
  const config = data.config;
  const reportUrl =
    config.publicUrl === null
      ? '/api/v1/crash-reports'
      : `${config.publicUrl}/api/v1/crash-reports`;
  return (
    <>
      <div className="stat-grid">
        <StatCard
          label="База"
          value={db.name}
          hint={`${db.user} · схема ${db.schema}`}
          tone="good"
        />
        <StatCard
          label="Роль только для чтения"
          value={db.readOnlyRole || 'не задана'}
          hint={db.readOnly ? 'членство подтверждено' : 'проверьте права'}
          tone={db.readOnly ? 'good' : 'bad'}
        />
        <StatCard
          label="Версия панели"
          value={service.version}
          hint={`запущена ${formatDateTime(service.startedAt)}`}
        />
        <StatCard
          label="Аптайм"
          value={formatDuration(service.uptimeSeconds)}
          hint={`${formatNumber(service.sessions)} сессий · ${formatNumber(service.operators)} операторов`}
        />
      </div>

      <div className="grid-2">
        <Card title="Данные координатора" subtitle="числа без секретов">
          <div className="mini-grid">
            <div>
              <span>учётные записи</span>
              <strong>{formatNumber(counts.accounts)}</strong>
            </div>
            <div>
              <span>активные устройства</span>
              <strong>{formatNumber(counts.devicesActive)}</strong>
            </div>
            <div>
              <span>узлы</span>
              <strong>{formatNumber(counts.nodesActive)}</strong>
            </div>
            <div>
              <span>сегменты</span>
              <strong>{formatNumber(counts.segments)}</strong>
            </div>
            <div>
              <span>фрагменты</span>
              <strong>{formatNumber(counts.fragments)}</strong>
            </div>
            <div>
              <span>аудиты</span>
              <strong>{formatNumber(counts.audits)}</strong>
            </div>
            <div>
              <span>задания ремонта</span>
              <strong>{formatNumber(counts.repairJobs)}</strong>
            </div>
            <div>
              <span>кредитные счета</span>
              <strong>{formatNumber(counts.creditAccounts)}</strong>
            </div>
            <div>
              <span>проводки</span>
              <strong>{formatNumber(counts.creditEntries)}</strong>
            </div>
          </div>
          <p className="muted small-text">
            <code>{db.version}</code>
          </p>
        </Card>

        <Card title="Отчёты о сбоях" subtitle="приёмник и хранение">
          <dl className="kv-list">
            <KeyValue label="Приёмник">
              <code>{reportUrl}</code>
            </KeyValue>
            <KeyValue label="Сохранение">
              {formatNumber(service.reports.total)} отчётов ·{' '}
              {formatNumber(service.reports.last24h)} за 24 ч
            </KeyValue>
            <KeyValue label="Срок хранения">{config.reportRetentionDays} дн.</KeyValue>
            <KeyValue label="Предел приёма">{config.reportPerHour} в час на адрес</KeyValue>
            <KeyValue label="Папка">{config.reportsDir}</KeyValue>
          </dl>
          <p className="muted small-text">
            Отчёты не содержат имени учётной записи, адреса клиента и путей:
            очистка выполняется и в приложении, и на сервере.
          </p>
        </Card>
      </div>

      <div className="grid-2">
        <Card title="Настройки панели" subtitle="listen, сессии и сеть">
          <dl className="kv-list">
            <KeyValue label="Адрес">
              <code>
                {config.host}:{config.port}
              </code>
            </KeyValue>
            <KeyValue label="Внешний адрес">{config.publicUrl ?? 'не задан'}</KeyValue>
            <KeyValue label="Cookie">
              {config.cookieSecure ? 'Secure, HttpOnly, SameSite=Strict' : 'без Secure (стенд)'}
            </KeyValue>
            <KeyValue label="X-Forwarded-For">
              {config.trustForwardedFor ? 'доверяем прокси' : 'не доверяем'}
            </KeyValue>
            <KeyValue label="Сессия">{config.sessionHours} ч</KeyValue>
            <KeyValue label="Статика">
              <code>{config.staticDir}</code>
            </KeyValue>
            <KeyValue label="Окно online">{config.onlineWindowMinutes} мин</KeyValue>
            <KeyValue label="Испытательный срок">{config.probationHours} ч</KeyValue>
          </dl>
        </Card>

        <Card title="Экономика" subtitle="тарифы панели должны совпадать с координатором">
          <dl className="kv-list">
            <KeyValue label="Хранение 1 ТБ·мес">
              {formatNumber(config.economy.dataCreditsPerTbMonth)} CR
            </KeyValue>
            <KeyValue label="Хранителю за 1 ТБ·мес">
              {formatNumber(config.economy.storeCreditsPerTbMonth)} CR
            </KeyValue>
            <KeyValue label="Бартер">{config.economy.barterRatio.toFixed(1)} : 1</KeyValue>
            <KeyValue label="Стартовый грант">
              {formatNumber(config.economy.starterCredits)} CR
            </KeyValue>
            <KeyValue label="Льготный период">
              {config.economy.graceDays} дн.
            </KeyValue>
          </dl>
          <div className="notice notice-info">
            <Icon name="eye" size={16} />
            <span>
              Смена блокировки, отзыва устройства и исключения узла — только
              командой <code>coordinator admin</code> с причиной и журналом.
            </span>
          </div>
        </Card>
      </div>

      <Card title="Как это устроено">
        <ul className="doc-list">
          <li>
            Панель читает базу координатора под ролью{' '}
            <code>{db.readOnlyRole || 'fs_admin_web'}</code>: SELECT и ничего
            больше. Секреты (KeyBundle, <code>auth_verifier</code>, сертификаты,
            блобы) роли не выданы.
          </li>
          <li>
            Отчёты о сбоях приходят на <code>POST /api/v1/crash-reports</code>{' '}
            от приложений с согласием пользователя и хранятся в папке панели.
          </li>
          <li>
            Доступ — по имени и паролю оператора; сессии в памяти, cookie
            <code> HttpOnly</code> и <code>SameSite=Strict</code>. Вход
            ограничен по частоте и неудачным попыткам.
          </li>
          <li>
            Адрес приёмника вшивается в приложение:{' '}
            <code>--dart-define=CRASH_REPORT_URL=…</code>.
          </li>
        </ul>
        <p className="muted small-text">
          Подробнее — <code>docs/ops/admin.md</code>,{' '}
          <code>docs/spec/crash-reports.md</code>, ADR-007 и ADR-017.
        </p>
      </Card>

      {service.reports.byVersion.length > 0 && (
        <Card title="Версии в отчётах" subtitle="по всем принятым сбоям">
          <div className="rows">
            {service.reports.byVersion.map((version) => (
              <div className="row-line" key={version.name}>
                <code>{version.name}</code>
                <strong>{formatNumber(version.count)}</strong>
              </div>
            ))}
          </div>
        </Card>
      )}

      {service.reports.total === 0 && (
        <Card>
          <Empty title="Отчётов о сбоях ещё нет">
            Это нормально, пока приложения не отправляли сбои.
          </Empty>
        </Card>
      )}
    </>
  );
}
