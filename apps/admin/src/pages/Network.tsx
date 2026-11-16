import { useState } from 'react';
import { useFetch } from '../api';
import { BarChart, StackedBar } from '../components/charts';
import { Icon } from '../components/Icon';
import {
  Badge,
  Card,
  Empty,
  ErrorBox,
  Loading,
  Select,
  StatCard,
} from '../components/ui';
import {
  formatAgo,
  formatBytes,
  formatNumber,
  formatPercent,
  methodLabel,
  statusLabel,
} from '../lib/format';
import { Link, useTitle } from '../lib/router';
import type { Network, Page, RepairJob } from '../types';

export function NetworkPage() {
  useTitle('Сеть и данные');
  const [hours, setHours] = useState('24');
  const { data, loading, error, reload } = useFetch<Network>(
    `/api/network?hours=${hours}`,
  );
  const jobs = useFetch<Page<RepairJob>>('/api/repair-jobs?state=open&limit=8');
  return (
    <div className="page">
      <header className="page-head">
        <div>
          <h1>Сеть и данные</h1>
          <p className="muted">
            Живые фрагменты, аудиты, ремонт, relay и трафик за выбранный период.
          </p>
        </div>
        <div className="head-actions">
          <Select
            value={hours}
            onChange={setHours}
            options={[
              { value: '6', label: '6 часов' },
              { value: '24', label: '24 часа' },
              { value: '72', label: '3 дня' },
              { value: '168', label: '7 дней' },
              { value: '720', label: '30 дней' },
            ]}
          />
          <button type="button" className="button" onClick={reload}>
            <Icon name="refresh" size={16} /> Обновить
          </button>
        </div>
      </header>
      {loading && !data && <Loading />}
      {error && <ErrorBox message={error} onRetry={reload} />}
      {data && <Body data={data} jobs={jobs.data} />}
    </div>
  );
}

function Body({
  data,
  jobs,
}: {
  data: Network;
  jobs: Page<RepairJob> | null;
}) {
  const { stats, relay, repair, audits } = data;
  const segments = Object.values(stats.segments).reduce((a, b) => a + b, 0);
  const liveHistogram = Object.entries(repair.queue.byLive).map(([live, count]) => ({
    label: `${live} живых`,
    value: count,
  }));
  const trafficTotal = Object.values(relay.traffic).reduce(
    (sum, item) => sum + item.bytes,
    0,
  );
  const auditTotal = audits.passed + audits.failed;
  return (
    <>
      <div className="stat-grid">
        <StatCard
          label="Сегменты"
          value={formatNumber(segments)}
          hint={`${formatNumber(repair.queue.segments)} в очереди ремонта`}
          tone={repair.queue.segments > 0 ? 'warn' : 'good'}
        />
        <StatCard
          label="Здоровых сегментов"
          value={formatNumber(stats.segments.ok ?? 0)}
          hint={`минимум ${repair.minLive ?? '—'} на сегмент · ${formatNumber(repair.nodesLost)} узлов потеряно`}
        />
        <StatCard
          label="Аудиты"
          value={`${formatNumber(audits.passed)} / ${formatNumber(auditTotal)}`}
          hint={`${auditTotal > 0 ? formatPercent(audits.passed / auditTotal) : '—'} пройдено · ${audits.latencyMs ?? '—'} мс`}
          tone={audits.failed > 0 ? 'warn' : 'good'}
        />
        <StatCard
          label="Трафик"
          value={formatBytes(trafficTotal)}
          hint={`relay ${relay.relayShare === null ? '—' : formatPercent(relay.relayShare)} · ${formatNumber(relay.nodesOnRelay)} узлов на relay`}
        />
        <StatCard
          label="Ремонт"
          value={formatNumber(repair.jobs.running + repair.jobs.verifying)}
          hint={`восстановлено ${formatNumber(repair.fragmentsRestored)} фрагментов`}
        />
        <StatCard
          label="Трафик ремонта"
          value={formatBytes(
            repair.traffic.downloadedBytes + repair.traffic.uploadedBytes,
          )}
          hint={`${repair.traffic.bytesPerTbPerDay === null ? '—' : formatBytes(repair.traffic.bytesPerTbPerDay)} на ТБ·сутки`}
        />
      </div>

      <div className="grid-2">
        <Card title="Состояние сегментов" subtitle="по числу живых фрагментов">
          <StackedBar
            parts={[
              { label: 'здоровы', value: stats.segments.ok ?? 0, color: '#0f6b5c' },
              { label: 'ремонт', value: stats.segments.repair ?? 0, color: '#b7791f' },
              { label: 'размещаются', value: stats.segments.pending ?? 0, color: '#8b949e' },
            ]}
          />
          <h3 className="subhead">Очередь ремонта по живым</h3>
          {liveHistogram.length === 0 ? (
            <Empty title="Очередь пуста" />
          ) : (
            <BarChart data={liveHistogram} height={130} />
          )}
        </Card>

        <Card title="Relay" subtitle={`${relay.relays.length} серверов · ${relay.days} суток`}>
          {relay.relays.length === 0 ? (
            <Empty title="Отчётов relay нет" />
          ) : (
            <div className="table-wrap">
              <table className="table compact">
                <thead>
                  <tr>
                    <th>Relay</th>
                    <th className="num">Слушателей</th>
                    <th className="num">Сеансов</th>
                    <th className="num">Трафик</th>
                    <th className="num">Узлов</th>
                    <th>Отчёт</th>
                  </tr>
                </thead>
                <tbody>
                  {relay.relays.map((item) => (
                    <tr key={item.relay}>
                      <td>
                        <code>{item.relay}</code>
                      </td>
                      <td className="num">{formatNumber(item.listeners)}</td>
                      <td className="num">{formatNumber(item.sessions)}</td>
                      <td className="num">{formatBytes(item.bytes)}</td>
                      <td className="num">{formatNumber(item.nodesAssigned)}</td>
                      <td>{formatAgo(item.lastReportAt)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <div className="legend legend-wrap">
            {Object.entries(relay.traffic).map(([method, item]) => (
              <span key={method}>
                <i />
                {methodLabel(method)}: {formatBytes(item.bytes)} ·{' '}
                {formatNumber(item.connections)} соединений
              </span>
            ))}
          </div>
        </Card>
      </div>

      <div className="grid-2">
        <Card title="Ремонт" subtitle={`за ${repair.hours} ч`}>
          <div className="mini-grid">
            <div>
              <span>выполняется</span>
              <strong>{formatNumber(repair.jobs.running)}</strong>
            </div>
            <div>
              <span>проверяется</span>
              <strong>{formatNumber(repair.jobs.verifying)}</strong>
            </div>
            <div>
              <span>завершено</span>
              <strong>{formatNumber(repair.jobs.done)}</strong>
            </div>
            <div>
              <span>провалено</span>
              <strong className={repair.jobs.failed > 0 ? 'bad-text' : ''}>
                {formatNumber(repair.jobs.failed)}
              </strong>
            </div>
            <div>
              <span>исполнителей приостановлено</span>
              <strong>{formatNumber(repair.executorsSuspended)}</strong>
            </div>
            <div>
              <span>переносы</span>
              <strong>
                {formatNumber(repair.relocations.running)} идут ·{' '}
                {formatNumber(repair.relocations.done)} готовы
              </strong>
            </div>
          </div>
          <KeyLine
            label="Трафик ремонта"
            value={`${formatBytes(repair.traffic.downloadedBytes + repair.traffic.uploadedBytes)} · модель ${formatBytes(repair.traffic.modelBytesPerTbPerDay)} на ТБ·сутки`}
          />
          <KeyLine
            label="Хранимые данные"
            value={formatBytes(repair.storedDataBytes)}
          />
          <KeyLine
            label="Неудачные проверки новых фрагментов"
            value={formatNumber(repair.fragmentsFailedAudit)}
          />
        </Card>

        <Card title="Аудиты" subtitle={`${formatNumber(auditTotal)} за ${data.hours} ч`}>
          <div className="audit-summary">
            <div className="audit-pass">
              <strong>{formatPercent(auditTotal > 0 ? audits.passed / auditTotal : 0)}</strong>
              <span>пройдено</span>
            </div>
            <div className="audit-bars">
              <span className="good-bg" style={{ flex: audits.passed || 1 }} />
              <span className="bad-bg" style={{ flex: audits.failed }} />
            </div>
          </div>
          <h3 className="subhead">Причины провалов</h3>
          {audits.reasons.length === 0 ? (
            <Empty title="Провалов нет" />
          ) : (
            <div className="rows">
              {audits.reasons.map((reason) => (
                <div className="row-line" key={reason.reason}>
                  <span>{reason.reason}</span>
                  <strong>{formatNumber(reason.count)}</strong>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      <Card
        title="Активные задания ремонта"
        subtitle="исполнители и прогресс"
        actions={<Link to="/segments?state=repair">сегменты в ремонте →</Link>}
      >
        {!jobs || jobs.items.length === 0 ? (
          <Empty title="Активных заданий нет" />
        ) : (
          <div className="table-wrap">
            <table className="table compact">
              <thead>
                <tr>
                  <th>Создано</th>
                  <th>Сегмент</th>
                  <th>Исполнитель</th>
                  <th>Вид</th>
                  <th>Состояние</th>
                  <th className="num">Цели</th>
                  <th className="num">Трафик</th>
                </tr>
              </thead>
              <tbody>
                {jobs.items.map((job) => (
                  <tr key={job.jobId}>
                    <td>{formatAgo(job.createdAt)}</td>
                    <td>
                      <Link
                        to={`/segments/${job.accountId}/${job.segmentId}`}
                        className="mono"
                      >
                        {job.segmentId.slice(0, 10)}…
                      </Link>
                    </td>
                    <td>
                      <Link to={`/nodes/${job.executorNodeId}`} className="mono">
                        {job.executorNodeId.slice(0, 10)}…
                      </Link>
                    </td>
                    <td>{job.kind === 'relocate' ? 'перенос' : 'ремонт'}</td>
                    <td>
                      <Badge tone="warn">{statusLabel(job.state)}</Badge>
                    </td>
                    <td className="num">
                      {job.targetsDone} / {job.targetsTotal}
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

      <Card title="Последние аудиты" subtitle="что проверялось и чем закончилось">
        {audits.recent.length === 0 ? (
          <Empty title="Аудитов нет" />
        ) : (
          <div className="table-wrap">
            <table className="table compact">
              <thead>
                <tr>
                  <th>Когда</th>
                  <th>Узел</th>
                  <th>Владелец</th>
                  <th>Итог</th>
                  <th className="num">Ответ</th>
                  <th>Причина</th>
                </tr>
              </thead>
              <tbody>
                {audits.recent.slice(0, 15).map((audit, index) => (
                  <tr key={`${audit.at}-${index}`}>
                    <td>{formatAgo(audit.at)}</td>
                    <td>
                      <Link to={`/nodes/${audit.nodeId}`} className="mono">
                        {audit.nodeId.slice(0, 10)}…
                      </Link>
                    </td>
                    <td>{audit.ownerLogin ?? '—'}</td>
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
    </>
  );
}

function KeyLine({ label, value }: { label: string; value: string }) {
  return (
    <div className="key-line">
      <span className="muted">{label}</span>
      <strong>{value}</strong>
    </div>
  );
}
