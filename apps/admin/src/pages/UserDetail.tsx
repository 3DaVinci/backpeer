import { useFetch } from '../api';
import { BarChart } from '../components/charts';
import { Icon } from '../components/Icon';
import {
  Badge,
  Card,
  CopyId,
  Empty,
  ErrorBox,
  KeyValue,
  Loading,
  ProgressBar,
} from '../components/ui';
import {
  formatAgo,
  formatBytes,
  formatCredits,
  formatDate,
  formatDateTime,
  formatNumber,
  formatPercent,
  ledgerKind,
  methodLabel,
  statusLabel,
} from '../lib/format';
import { Link, useTitle } from '../lib/router';
import type { AccountDetail } from '../types';

export function UserDetail({ accountId }: { accountId: string }) {
  useTitle('Учётная запись');
  const { data, loading, error, reload } = useFetch<AccountDetail>(
    `/api/users/${encodeURIComponent(accountId)}`,
  );
  return (
    <div className="page">
      <Link to="/users" className="back-link">
        <Icon name="back" size={15} /> К списку пользователей
      </Link>
      {loading && !data && <Loading />}
      {error && <ErrorBox message={error} onRetry={reload} />}
      {data && <Body account={data} onReload={reload} />}
    </div>
  );
}

function Body({
  account,
  onReload,
}: {
  account: AccountDetail;
  onReload: () => void;
}) {
  const trafficByDay = new Map<string, number>();
  for (const entry of account.traffic) {
    trafficByDay.set(entry.day, (trafficByDay.get(entry.day) ?? 0) + entry.bytes);
  }
  const quota = account.quota;
  const maxBytes = Math.max(quota.maxBytes, quota.dataBytes, 1);
  return (
    <>
      <header className="page-head">
        <div>
          <div className="title-row">
            <h1>{account.login ?? 'Без имени'}</h1>
            {account.blockedAt ? (
              <Badge tone="bad">заблокирована</Badge>
            ) : account.negativeSince ? (
              <Badge tone="warn">в долге</Badge>
            ) : (
              <Badge tone="good">активна</Badge>
            )}
            {account.keyCopy ? (
              <Badge tone="info">копия ключа на сервере</Badge>
            ) : null}
          </div>
          <p className="muted">
            <CopyId value={account.accountId} head={16} /> · создана{' '}
            {formatDateTime(account.createdAt)}
          </p>
        </div>
        <button type="button" className="button" onClick={onReload}>
          <Icon name="refresh" size={16} /> Обновить
        </button>
      </header>

      {account.blockedAt && (
        <div className="notice notice-bad">
          <Icon name="alert" />
          <div>
            <strong>Учётная запись заблокирована</strong>
            <p>
              {formatDateTime(account.blockedAt)}
              {account.blockedReason ? ` · ${account.blockedReason}` : ''}.
              Разблокировка — <code>coordinator admin account unblock</code>.
            </p>
          </div>
        </div>
      )}

      <div className="stat-grid">
        <div className="stat">
          <span className="stat-label">Баланс</span>
          <strong className={`stat-value ${account.balanceMc < 0 ? 'bad-text' : ''}`}>
            {formatCredits(account.balanceMc)}
          </strong>
          <span className="stat-hint">
            {account.negativeSince
              ? `долг с ${formatDate(account.negativeSince)}`
              : 'без долга'}
          </span>
        </div>
        <div className="stat">
          <span className="stat-label">Данные</span>
          <strong className="stat-value">{formatBytes(quota.dataBytes)}</strong>
          <span className="stat-hint">
            сверх квоты {formatBytes(quota.billableBytes)}
          </span>
        </div>
        <div className="stat">
          <span className="stat-label">Устройства</span>
          <strong className="stat-value">
            {formatNumber(account.devices.filter((d) => !d.revokedAt).length)}
          </strong>
          <span className="stat-hint">
            отозвано {formatNumber(account.devices.filter((d) => d.revokedAt).length)}
          </span>
        </div>
        <div className="stat">
          <span className="stat-label">Хранители</span>
          <strong className="stat-value">{formatNumber(account.nodes.length)}</strong>
          <span className="stat-hint">
            {formatNumber(account.nodes.filter((n) => n.online).length)} в сети ·{' '}
            {formatBytes(
              account.nodes.reduce((sum, node) => sum + node.capacityBytes, 0),
            )}{' '}
            ёмкости
          </span>
        </div>
      </div>

      <div className="grid-2">
        <Card title="Квота и кредиты" subtitle="бартер 2,5 : 1, стартовый грант 600 CR">
          <div className="quota-row">
            <div>
              <span>занято</span>
              <strong>{formatBytes(quota.dataBytes)}</strong>
            </div>
            <div>
              <span>доступно</span>
              <strong>{formatBytes(quota.maxBytes)}</strong>
            </div>
          </div>
          <ProgressBar
            value={quota.dataBytes}
            max={maxBytes}
            tone={quota.blocked ? 'bad' : 'accent'}
            label="Занятое место"
          />
          <KeyValue label="Бесплатная квота">
            {formatBytes(quota.barterBytes)} (ёмкость хранителей / 2,5)
          </KeyValue>
          <KeyValue label="Стоимость сверх квоты">
            {formatCredits(quota.monthlyCostMc)} в месяц ·{' '}
            {formatCredits(quota.dailyCostMc)} в сутки
          </KeyValue>
          <KeyValue label="Начислено всего">{formatCredits(quota.earnedMc)}</KeyValue>
          <KeyValue label="Списано всего">{formatCredits(quota.spentMc)}</KeyValue>
          <KeyValue label="Льготный период">
            {quota.graceDays} дн.
            {quota.graceUntil ? ` · до ${formatDateTime(quota.graceUntil)}` : ''}
          </KeyValue>
          {quota.blocked && (
            <p className="bad-text">
              Новые данные запрещены: долг дольше льготного периода. Сохранённые
              данные не удаляются.
            </p>
          )}
        </Card>

        <Card title="Место и бэкапы">
          <div className="mini-grid">
            <div>
              <span>снимки и индексы</span>
              <strong>{formatBytes(account.objectBytes)}</strong>
            </div>
            <div>
              <span>фрагменты</span>
              <strong>{formatBytes(account.fragmentBytes)}</strong>
            </div>
            <div>
              <span>копия ключа</span>
              <strong>
                {account.keyCopy
                  ? formatDateTime(account.keyCopyUpdatedAt)
                  : 'нет'}
              </strong>
            </div>
            <div>
              <span>сегментов</span>
              <strong>
                {formatNumber(
                  account.segments.reduce((sum, item) => sum + item.count, 0),
                )}
              </strong>
            </div>
          </div>
          <h3 className="subhead">Сегменты по состоянию</h3>
          {account.segments.length === 0 ? (
            <Empty title="Бэкапов нет" />
          ) : (
            <div className="rows">
              {account.segments.map((item) => (
                <div className="row-line" key={item.state}>
                  <Badge
                    tone={
                      item.state === 'ok'
                        ? 'good'
                        : item.state === 'repair'
                          ? 'warn'
                          : 'neutral'
                    }
                  >
                    {statusLabel(item.state)}
                  </Badge>
                  <span>{formatNumber(item.count)}</span>
                  <span className="muted">{formatBytes(item.bytes)}</span>
                </div>
              ))}
            </div>
          )}
          <h3 className="subhead">Объекты</h3>
          {account.objects.length === 0 ? (
            <Empty title="Объектов нет" />
          ) : (
            <div className="rows">
              {account.objects.map((item) => (
                <div className="row-line" key={item.kind}>
                  <span>{item.kind === 'snapshots' ? 'снимки' : 'индексы'}</span>
                  <span>{formatNumber(item.count)}</span>
                  <span className="muted">{formatBytes(item.bytes)}</span>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      <div className="grid-2">
        <Card title="Устройства" subtitle="отзыв — через CLI, с журналом">
          {account.devices.length === 0 ? (
            <Empty title="Устройств нет" />
          ) : (
            <div className="table-wrap">
              <table className="table compact">
                <thead>
                  <tr>
                    <th>Ключ устройства</th>
                    <th>Добавлено</th>
                    <th>Состояние</th>
                  </tr>
                </thead>
                <tbody>
                  {account.devices.map((device) => (
                    <tr key={device.deviceId}>
                      <td>
                        <CopyId value={device.deviceId} head={12} />
                      </td>
                      <td>{formatDateTime(device.addedAt)}</td>
                      <td>
                        {device.revokedAt ? (
                          <Badge tone="bad" title={`отозвано ${formatDateTime(device.revokedAt)}`}>
                            отозвано
                            {device.revokedBy === 'operator' ? ' оператором' : ''}
                          </Badge>
                        ) : (
                          <Badge tone="good">активно</Badge>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
        <Card title="Хранители" subtitle="узлы этой учётной записи">
          {account.nodes.length === 0 ? (
            <Empty title="Узлов нет" />
          ) : (
            <div className="table-wrap">
              <table className="table compact">
                <thead>
                  <tr>
                    <th>Узел</th>
                    <th>Состояние</th>
                    <th className="num">Ёмкость</th>
                    <th>Последний heartbeat</th>
                  </tr>
                </thead>
                <tbody>
                  {account.nodes.map((node) => (
                    <tr key={node.nodeId}>
                      <td>
                        <Link to={`/nodes/${node.nodeId}`} className="mono">
                          {node.nodeId.slice(0, 12)}…
                        </Link>
                      </td>
                      <td>
                        <Badge
                          tone={
                            node.online
                              ? 'good'
                              : node.removedAt
                                ? 'neutral'
                                : 'warn'
                          }
                        >
                          {node.online
                            ? 'в сети'
                            : node.removedAt
                              ? 'удалён'
                              : 'не в сети'}
                        </Badge>
                      </td>
                      <td className="num">
                        {formatBytes(node.usedBytes)}{' '}
                        <span className="muted">из {formatBytes(node.capacityBytes)}</span>
                      </td>
                      <td>{formatAgo(node.lastHeartbeatAt)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>

      <div className="grid-2">
        <Card title="Трафик за 14 дней" subtitle="по отчётам клиентов и узлов">
          {trafficByDay.size === 0 ? (
            <Empty title="Отчётов о трафике нет" />
          ) : (
            <BarChart
              data={[...trafficByDay.entries()].map(([day, bytes]) => ({
                label: day.slice(5),
                value: bytes,
              }))}
              format={(value) => formatBytes(value)}
            />
          )}
          <div className="legend legend-wrap">
            {[...new Set(account.traffic.map((t) => t.method))].map((method) => (
              <span key={method}>
                <i />
                {methodLabel(method)}
              </span>
            ))}
          </div>
          {account.relay.length > 0 && (
            <>
              <h3 className="subhead">Relay</h3>
              <div className="rows">
                {account.relay.slice(-7).map((entry) => (
                  <div className="row-line" key={entry.day}>
                    <span>{entry.day}</span>
                    <span>{formatBytes(entry.bytes)}</span>
                    <span className="muted">{formatNumber(entry.sessions)} сеансов</span>
                  </div>
                ))}
              </div>
            </>
          )}
        </Card>

        <Card
          title="Журнал кредитов"
          subtitle="последние 50 проводок"
          actions={<Link to="/economy">вся экономика →</Link>}
        >
          {account.ledger.length === 0 ? (
            <Empty title="Проводок нет" />
          ) : (
            <div className="table-wrap scroll">
              <table className="table compact">
                <thead>
                  <tr>
                    <th>Когда</th>
                    <th>Операция</th>
                    <th className="num">Сумма</th>
                    <th>Примечание</th>
                  </tr>
                </thead>
                <tbody>
                  {account.ledger.map((entry, index) => (
                    <tr key={`${entry.createdAt}-${index}`}>
                      <td>{formatDate(entry.createdAt ?? entry.day)}</td>
                      <td>{ledgerKind(entry.kind)}</td>
                      <td
                        className={`num ${entry.amountMc < 0 ? 'bad-text' : 'good-text'}`}
                      >
                        {entry.amountMc > 0 ? '+' : ''}
                        {formatCredits(entry.amountMc)}
                      </td>
                      <td className="muted">{entry.note || entry.ref}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>

      <p className="muted small-text">
        Доля доступности узлов:{' '}
        {account.nodes.length > 0
          ? formatPercent(
              account.nodes.reduce((sum, node) => sum + node.availability, 0) /
                account.nodes.length,
            )
          : '—'}
        . Смена пароля, отзыв устройства и блокировка — только через{' '}
        <code>coordinator admin</code>.
      </p>
    </>
  );
}
