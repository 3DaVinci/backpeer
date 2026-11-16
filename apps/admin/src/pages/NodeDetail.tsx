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
  countryName,
  formatAgo,
  formatBytes,
  formatDateTime,
  formatNumber,
  formatPercent,
  statusLabel,
} from '../lib/format';
import { Link, useTitle } from '../lib/router';
import type { NodeDetail } from '../types';

export function NodeDetail({ nodeId }: { nodeId: string }) {
  useTitle('Хранитель');
  const { data, loading, error, reload } = useFetch<NodeDetail>(
    `/api/nodes/${encodeURIComponent(nodeId)}`,
  );
  return (
    <div className="page">
      <Link to="/nodes" className="back-link">
        <Icon name="back" size={15} /> К реестру хранителей
      </Link>
      {loading && !data && <Loading />}
      {error && <ErrorBox message={error} onRetry={reload} />}
      {data && <Body node={data} onReload={reload} />}
    </div>
  );
}

function Body({ node, onReload }: { node: NodeDetail; onReload: () => void }) {
  const used = Math.max(node.usedBytes, node.assignedBytes);
  return (
    <>
      <header className="page-head">
        <div>
          <div className="title-row">
            <h1>Узел</h1>
            <Badge
              tone={
                node.status === 'online'
                  ? 'good'
                  : node.status === 'lost' ||
                      node.status === 'excluded' ||
                      node.status === 'removed'
                    ? 'bad'
                    : 'warn'
              }
            >
              {statusLabel(node.status)}
            </Badge>
            {node.onProbation && <Badge tone="info">испытательный срок</Badge>}
            {node.relay && <Badge tone="neutral">через relay {node.relay}</Badge>}
          </div>
          <p className="muted">
            <CopyId value={node.nodeId} head={20} /> · владелец{' '}
            {node.ownerLogin ? (
              <Link to={`/users/${node.accountId}`}>{node.ownerLogin}</Link>
            ) : (
              '—'
            )}
          </p>
        </div>
        <button type="button" className="button" onClick={onReload}>
          <Icon name="refresh" size={16} /> Обновить
        </button>
      </header>

      {node.excludedAt && (
        <div className="notice notice-bad">
          <Icon name="alert" />
          <div>
            <strong>Узел исключён из размещения</strong>
            <p>
              {formatDateTime(node.excludedAt)}
              {node.excludedReason ? ` · ${node.excludedReason}` : ''}. Возврат —
              <code> coordinator admin node include</code>.
            </p>
          </div>
        </div>
      )}

      <div className="stat-grid">
        <div className="stat">
          <span className="stat-label">Занято</span>
          <strong className="stat-value">{formatBytes(used)}</strong>
          <span className="stat-hint">из {formatBytes(node.capacityBytes)}</span>
        </div>
        <div className="stat">
          <span className="stat-label">Доступность</span>
          <strong className="stat-value">{formatPercent(node.availability)}</strong>
          <span className="stat-hint">
            {formatAgo(node.lastHeartbeatAt)} · {node.auditLatencyMs ?? '—'} мс аудит
          </span>
        </div>
        <div className="stat">
          <span className="stat-label">Репутация</span>
          <strong className="stat-value">{node.reputation.toFixed(3)}</strong>
          <span className="stat-hint">вес при размещении</span>
        </div>
        <div className="stat">
          <span className="stat-label">Аудиты</span>
          <strong className="stat-value">
            {formatNumber(node.auditsPassed)} /{' '}
            {formatNumber(node.auditsPassed + node.auditsFailed)}
          </strong>
          <span className="stat-hint">
            {node.auditWindowFailures} провалов в окне ·{' '}
            {formatAgo(node.lastAuditAt)}
          </span>
        </div>
      </div>

      <div className="grid-2">
        <Card title="Ёмкость" subtitle="объявленная, занятая и выделенная">
          <ProgressBar
            value={used}
            max={node.capacityBytes}
            tone={used / Math.max(node.capacityBytes, 1) > 0.9 ? 'warn' : 'accent'}
            label="Занято"
          />
          <div className="mini-grid">
            <div>
              <span>capacity</span>
              <strong>{formatBytes(node.capacityBytes)}</strong>
            </div>
            <div>
              <span>used</span>
              <strong>{formatBytes(node.usedBytes)}</strong>
            </div>
            <div>
              <span>assigned</span>
              <strong>{formatBytes(node.assignedBytes)}</strong>
            </div>
            <div>
              <span>free</span>
              <strong>{formatBytes(node.freeBytes)}</strong>
            </div>
            <div>
              <span>живых фрагментов</span>
              <strong>{formatNumber(node.storedFragments)}</strong>
            </div>
            <div>
              <span>повреждено</span>
              <strong className={node.damagedFragments > 0 ? 'bad-text' : ''}>
                {formatNumber(node.damagedFragments)}
              </strong>
            </div>
          </div>
        </Card>

        <Card title="Сведения" subtitle="настройки и состояние узла">
          <dl className="kv-list">
            <KeyValue label="Зарегистрирован">
              {formatDateTime(node.registeredAt)}
            </KeyValue>
            <KeyValue label="Последний heartbeat">
              {formatDateTime(node.lastHeartbeatAt)} ({formatAgo(node.lastHeartbeatAt)})
            </KeyValue>
            <KeyValue label="Версия">{node.software || '—'}</KeyValue>
            <KeyValue label="Место">
              {node.country
                ? `${countryName(node.country)}${node.city ? `, ${node.city}` : ''}`
                : 'нет geoip'}
            </KeyValue>
            <KeyValue label="Relay">
              {node.relay ?? 'прямые адреса'}
              {node.relayUntil ? ` до ${formatDateTime(node.relayUntil)}` : ''}
            </KeyValue>
            <KeyValue label="Сегментов на узле">
              {formatNumber(node.segmentsCount)} · {formatBytes(node.storedBytes)}
            </KeyValue>
            {node.repairSuspendedUntil && (
              <KeyValue label="Ремонт приостановлен">
                до {formatDateTime(node.repairSuspendedUntil)}
              </KeyValue>
            )}
            {node.leavingAt && (
              <KeyValue label="Выход из сети">
                с {formatDateTime(node.leavingAt)}
              </KeyValue>
            )}
          </dl>
          <h3 className="subhead">Адреса из достижимости</h3>
          {node.endpoints && node.endpoints.length > 0 ? (
            <ul className="endpoints">
              {node.endpoints.map((endpoint) => (
                <li key={endpoint}>
                  <code>{endpoint}</code>
                </li>
              ))}
            </ul>
          ) : (
            <p className="muted small-text">
              Адресов нет: узел за NAT и ходит через relay.
            </p>
          )}
        </Card>
      </div>

      <Card title="Доступность за 30 дней" subtitle="доля 15-минутных интервалов с heartbeat">
        {node.uptime.length === 0 ? (
          <Empty title="Нет данных uptime" />
        ) : (
          <BarChart
            data={node.uptime.map((day) => ({
              label: day.day.slice(5),
              value: day.online,
            }))}
            format={(value) => formatPercent(value)}
            height={150}
          />
        )}
      </Card>

      <div className="grid-2">
        <Card title="Последние аудиты" subtitle="проверка случайного фрагмента">
          {node.audits.length === 0 ? (
            <Empty title="Аудитов ещё не было" />
          ) : (
            <div className="table-wrap">
              <table className="table compact">
                <thead>
                  <tr>
                    <th>Когда</th>
                    <th>Итог</th>
                    <th className="num">Ответ</th>
                    <th>Причина</th>
                  </tr>
                </thead>
                <tbody>
                  {node.audits.map((audit, index) => (
                    <tr key={`${audit.at}-${index}`}>
                      <td>{formatDateTime(audit.at)}</td>
                      <td>
                        <Badge tone={audit.passed ? 'good' : 'bad'}>
                          {audit.passed ? 'пройден' : 'провал'}
                        </Badge>
                        {audit.recheck && <Badge tone="warn">повтор</Badge>}
                      </td>
                      <td className="num">{audit.latencyMs} мс</td>
                      <td className="muted">{audit.reason ?? '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>

        <Card title="Задания ремонта" subtitle="где узел был исполнителем">
          {node.jobs.length === 0 ? (
            <Empty title="Заданий не было" />
          ) : (
            <div className="table-wrap">
              <table className="table compact">
                <thead>
                  <tr>
                    <th>Создано</th>
                    <th>Вид</th>
                    <th>Состояние</th>
                    <th className="num">Трафик</th>
                  </tr>
                </thead>
                <tbody>
                  {node.jobs.map((job) => (
                    <tr key={job.jobId}>
                      <td>{formatDateTime(job.createdAt)}</td>
                      <td>{job.kind === 'relocate' ? 'перенос' : 'ремонт'}</td>
                      <td>
                        <Badge
                          tone={
                            job.state === 'done'
                              ? 'good'
                              : job.state === 'failed'
                                ? 'bad'
                                : 'warn'
                          }
                        >
                          {statusLabel(job.state)}
                        </Badge>
                      </td>
                      <td className="num">
                        {formatBytes(job.bytesDownloaded + job.bytesUploaded)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>
    </>
  );
}
