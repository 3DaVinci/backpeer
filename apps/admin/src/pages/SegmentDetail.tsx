import { useFetch } from '../api';
import { Icon } from '../components/Icon';
import {
  Badge,
  Card,
  Empty,
  ErrorBox,
  KeyValue,
  Loading,
} from '../components/ui';
import {
  countryName,
  formatAgo,
  formatBytes,
  formatDateTime,
  statusLabel,
} from '../lib/format';
import { Link, useTitle } from '../lib/router';
import type { SegmentDetail } from '../types';

export function SegmentDetailPage({
  accountId,
  segmentId,
}: {
  accountId: string;
  segmentId: string;
}) {
  useTitle('Сегмент');
  const { data, loading, error, reload } = useFetch<SegmentDetail>(
    `/api/segments/${encodeURIComponent(accountId)}/${encodeURIComponent(segmentId)}`,
  );
  return (
    <div className="page">
      <Link to="/segments" className="back-link">
        <Icon name="back" size={15} /> К сегментам
      </Link>
      {loading && !data && <Loading />}
      {error && <ErrorBox message={error} onRetry={reload} />}
      {data && (
        <>
          <header className="page-head">
            <div>
              <div className="title-row">
                <h1>Сегмент</h1>
                <Badge
                  tone={
                    data.state === 'ok'
                      ? 'good'
                      : data.state === 'repair'
                        ? 'warn'
                        : 'neutral'
                  }
                >
                  {statusLabel(data.state)}
                </Badge>
              </div>
              <p className="muted mono">{data.segmentId}</p>
            </div>
            <button type="button" className="button" onClick={reload}>
              <Icon name="refresh" size={16} /> Обновить
            </button>
          </header>

          <div className="stat-grid">
            <div className="stat">
              <span className="stat-label">Схема</span>
              <strong className="stat-value">
                {data.k} из {data.n}
              </strong>
              <span className="stat-hint">порог ремонта {data.repairThreshold}</span>
            </div>
            <div className="stat">
              <span className="stat-label">Живых фрагментов</span>
              <strong
                className={`stat-value ${data.live < data.k ? 'bad-text' : ''}`}
              >
                {data.live}
              </strong>
              <span className="stat-hint">
                сохранено {data.fragments.filter((f) => f.stored).length}
              </span>
            </div>
            <div className="stat">
              <span className="stat-label">Данные</span>
              <strong className="stat-value">{formatBytes(data.dataBytes)}</strong>
              <span className="stat-hint">
                фрагмент {formatBytes(data.fragmentSize)}
              </span>
            </div>
            <div className="stat">
              <span className="stat-label">Размещён</span>
              <strong className="stat-value">{formatDateTime(data.allocatedAt)}</strong>
              <span className="stat-hint">
                {data.repairSince
                  ? `ремонт с ${formatAgo(data.repairSince)}`
                  : 'ремонт не требуется'}
              </span>
            </div>
          </div>

          <Card title="Фрагменты" subtitle="по индексам: где хранятся и проверены ли аудитом">
            {data.fragments.length === 0 ? (
              <Empty title="Фрагментов нет" />
            ) : (
              <div className="table-wrap">
                <table className="table compact">
                  <thead>
                    <tr>
                      <th className="num">#</th>
                      <th>Узел</th>
                      <th>Владелец</th>
                      <th>Место</th>
                      <th>Состояние</th>
                      <th>Аудит</th>
                      <th>Heartbeat</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.fragments.map((fragment) => (
                      <tr key={fragment.idx}>
                        <td className="num">{fragment.idx}</td>
                        <td>
                          <Link to={`/nodes/${fragment.nodeId}`} className="mono">
                            {fragment.nodeId.slice(0, 10)}…
                          </Link>
                        </td>
                        <td>{fragment.ownerLogin ?? '—'}</td>
                        <td>
                          {fragment.country
                            ? `${countryName(fragment.country)}${fragment.city ? `, ${fragment.city}` : ''}`
                            : '—'}
                        </td>
                        <td>
                          {fragment.damagedAt ? (
                            <Badge tone="bad">повреждён</Badge>
                          ) : fragment.stored ? (
                            <Badge tone="good">сохранён</Badge>
                          ) : (
                            <Badge tone="neutral">не сохранён</Badge>
                          )}
                          {fragment.auditFailedAt && (
                            <Badge tone="bad">аудит не пройден</Badge>
                          )}
                        </td>
                        <td>
                          {fragment.auditedAt
                            ? formatDateTime(fragment.auditedAt)
                            : 'не проверялся'}
                        </td>
                        <td>{formatAgo(fragment.nodeLastHeartbeatAt)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>

          <Card title="Размещение" subtitle="владелец и ключи">
            <dl className="kv-list">
              <KeyValue label="Учётная запись">
                {data.login ? (
                  <Link to={`/users/${data.accountId}`}>{data.login}</Link>
                ) : (
                  <code>{data.accountId}</code>
                )}
              </KeyValue>
              <KeyValue label="Segment ID">
                <code>{data.segmentId}</code>
              </KeyValue>
              <KeyValue label="Выделен">
                {formatDateTime(data.allocatedAt)}
              </KeyValue>
              <KeyValue label="Зафиксирован">
                {data.committedAt ? formatDateTime(data.committedAt) : '—'}
              </KeyValue>
            </dl>
          </Card>
        </>
      )}
    </div>
  );
}
