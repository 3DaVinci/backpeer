import { useEffect, useState } from 'react';
import { useFetch } from '../api';
import { Icon } from '../components/Icon';
import {
  Badge,
  Card,
  DownloadButton,
  Dot,
  Empty,
  ErrorBox,
  Loading,
  Pagination,
  ProgressBar,
  SearchField,
  Select,
  Tabs,
  Toolbar,
} from '../components/ui';
import {
  countryName,
  formatAgo,
  formatBytes,
  formatNumber,
  formatPercent,
  statusLabel,
} from '../lib/format';
import { Link, useTitle } from '../lib/router';
import { useDebounced } from '../lib/useDebounced';
import type { NodeSummary, Page } from '../types';

const filters = [
  { value: 'active', label: 'Действующие' },
  { value: 'all', label: 'Все' },
  { value: 'online', label: 'В сети' },
  { value: 'offline', label: 'Не в сети' },
  { value: 'lost', label: 'Потерянные' },
  { value: 'excluded', label: 'Исключённые' },
  { value: 'leaving', label: 'Выходят' },
  { value: 'probation', label: 'Испытательный срок' },
];

export function Nodes() {
  useTitle('Хранители');
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState('active');
  const [sort, setSort] = useState('last_seen');
  const [version, setVersion] = useState('');
  const [page, setPage] = useState(1);
  const debounced = useDebounced(query);
  useEffect(() => setPage(1), [debounced, filter, sort, version]);
  const path = `/api/nodes?${new URLSearchParams({
    query: debounced,
    filter,
    sort,
    version,
    page: String(page),
    limit: '25',
  })}`;
  const { data, loading, error, reload } = useFetch<Page<NodeSummary>>(path);

  return (
    <div className="page">
      <header className="page-head">
        <div>
          <h1>Хранители</h1>
          <p className="muted">
            Реестр узлов: доступность, ёмкость, аудиты, репутация и relay.
            Исключение узла — только через CLI.
          </p>
        </div>
        <div className="head-actions">
          <DownloadButton href="/api/export/nodes.csv" label="CSV" />
          <button type="button" className="button" onClick={reload}>
            <Icon name="refresh" size={16} /> Обновить
          </button>
        </div>
      </header>

      <Card>
        <Toolbar
          actions={
            <>
              <input
                className="version-input"
                placeholder="версия, например 0.0.7"
                value={version}
                onChange={(event) => setVersion(event.target.value.trim())}
                aria-label="Версия"
              />
              <Select
                value={sort}
                onChange={setSort}
                options={[
                  { value: 'last_seen', label: 'по heartbeat' },
                  { value: 'registered_desc', label: 'сначала новые' },
                  { value: 'capacity', label: 'по ёмкости' },
                  { value: 'used', label: 'по занятому месту' },
                  { value: 'availability', label: 'по доступности ↑' },
                  { value: 'audits', label: 'по провалам аудитов' },
                ]}
              />
            </>
          }
        >
          <SearchField
            value={query}
            onChange={setQuery}
            placeholder="Узел, владелец"
          />
          <Tabs value={filter} onChange={setFilter} options={filters} />
        </Toolbar>

        {loading && !data && <Loading />}
        {error && <ErrorBox message={error} onRetry={reload} />}
        {data && data.items.length === 0 && (
          <Empty title="Узлов не найдено">Измените фильтр или запрос.</Empty>
        )}
        {data && data.items.length > 0 && (
          <div className="table-wrap">
            <table className="table nodes-table">
              <thead>
                <tr>
                  <th>Узел</th>
                  <th>Владелец</th>
                  <th>Место</th>
                  <th>Состояние</th>
                  <th>Ёмкость</th>
                  <th className="num">Доступность</th>
                  <th className="num">Репутация</th>
                  <th>Аудиты</th>
                  <th>Версия</th>
                  <th>Heartbeat</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((node) => {
                  const used = Math.max(node.usedBytes, node.assignedBytes);
                  return (
                    <tr key={node.nodeId}>
                      <td>
                        <Link to={`/nodes/${node.nodeId}`} className="mono strong-link">
                          {node.nodeId.slice(0, 10)}…
                        </Link>
                        <div className="subline">
                          {node.relay ? (
                            <span className="muted">relay: {node.relay}</span>
                          ) : (
                            <span className="muted">
                              {node.endpointCount ?? 0} адресов
                            </span>
                          )}
                        </div>
                      </td>
                      <td>
                        {node.ownerLogin ? (
                          <Link to={`/users/${node.accountId}`}>
                            {node.ownerLogin}
                          </Link>
                        ) : (
                          '—'
                        )}
                      </td>
                      <td>
                        {node.country ? (
                          <span title={node.city ?? ''}>
                            {countryName(node.country)}
                            {node.city ? `, ${node.city}` : ''}
                          </span>
                        ) : (
                          <span className="muted">нет geoip</span>
                        )}
                      </td>
                      <td>
                        <span className="status-line">
                          <Dot
                            tone={
                              node.status === 'online'
                                ? 'good'
                                : node.status === 'leaving'
                                  ? 'warn'
                                  : node.status === 'excluded' ||
                                      node.status === 'lost'
                                    ? 'bad'
                                    : 'neutral'
                            }
                          />
                          {statusLabel(node.status)}
                          {node.onProbation && (
                            <Badge tone="info">испытание</Badge>
                          )}
                        </span>
                      </td>
                      <td className="capacity-cell">
                        <div className="capacity-line">
                          <span>{formatBytes(used)}</span>
                          <span className="muted">
                            / {formatBytes(node.capacityBytes)}
                          </span>
                        </div>
                        <ProgressBar
                          value={used}
                          max={node.capacityBytes}
                          tone={used / Math.max(node.capacityBytes, 1) > 0.9 ? 'warn' : 'accent'}
                          label="Занято"
                        />
                      </td>
                      <td className="num">{formatPercent(node.availability)}</td>
                      <td className="num">{node.reputation.toFixed(2)}</td>
                      <td>
                        <span className={node.auditsFailed > 0 ? 'bad-text' : ''}>
                          {formatNumber(node.auditsPassed)} /{' '}
                          {formatNumber(node.auditsPassed + node.auditsFailed)}
                        </span>
                        {node.auditWindowFailures > 0 && (
                          <div className="subline bad-text">
                            {node.auditWindowFailures} в окне
                          </div>
                        )}
                      </td>
                      <td>
                        <code className="small-code">{node.software || '—'}</code>
                      </td>
                      <td>{formatAgo(node.lastHeartbeatAt)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        {data && (
          <Pagination
            page={data.page}
            total={data.total}
            limit={data.limit}
            onChange={setPage}
          />
        )}
      </Card>
    </div>
  );
}
