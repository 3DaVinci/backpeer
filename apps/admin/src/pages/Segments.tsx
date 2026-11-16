import { useEffect, useState } from 'react';
import { useFetch } from '../api';
import { Icon } from '../components/Icon';
import {
  Badge,
  Card,
  CopyId,
  Empty,
  ErrorBox,
  Loading,
  Pagination,
  SearchField,
  Select,
  Tabs,
  Toolbar,
} from '../components/ui';
import {
  formatAgo,
  formatBytes,
  statusLabel,
} from '../lib/format';
import { Link, useTitle } from '../lib/router';
import { useDebounced } from '../lib/useDebounced';
import type { Page, SegmentSummary } from '../types';

const filters = [
  { value: 'all', label: 'Все' },
  { value: 'stored', label: 'Сохранённые' },
  { value: 'ok', label: 'Здоровые' },
  { value: 'repair', label: 'В ремонте' },
  { value: 'lost', label: 'Потерянные' },
  { value: 'pending', label: 'Размещаются' },
];

export function Segments() {
  useTitle('Сегменты');
  const [query, setQuery] = useState('');
  const [state, setState] = useState(
    new URLSearchParams(window.location.search).get('state') ?? 'all',
  );
  const [sort, setSort] = useState('allocated_desc');
  const [page, setPage] = useState(1);
  const debounced = useDebounced(query);
  useEffect(() => setPage(1), [debounced, state, sort]);
  const path = `/api/segments?${new URLSearchParams({
    query: debounced,
    state,
    sort,
    page: String(page),
    limit: '25',
  })}`;
  const { data, loading, error, reload } =
    useFetch<Page<SegmentSummary>>(path);

  return (
    <div className="page">
      <header className="page-head">
        <div>
          <h1>Сегменты</h1>
          <p className="muted">
            Сегменты бэкапов: k из n, живые фрагменты, ремонт и размещение.
            Содержимое фрагментов недоступно.
          </p>
        </div>
        <button type="button" className="button" onClick={reload}>
          <Icon name="refresh" size={16} /> Обновить
        </button>
      </header>
      <Card>
        <Toolbar
          actions={
            <Select
              value={sort}
              onChange={setSort}
              options={[
                { value: 'allocated_desc', label: 'сначала новые' },
                { value: 'allocated_asc', label: 'сначала старые' },
                { value: 'live', label: 'по живым ↑' },
                { value: 'size', label: 'по размеру' },
              ]}
            />
          }
        >
          <SearchField
            value={query}
            onChange={setQuery}
            placeholder="Владелец или segment_id"
          />
          <Tabs value={state} onChange={setState} options={filters} />
        </Toolbar>
        {loading && !data && <Loading />}
        {error && <ErrorBox message={error} onRetry={reload} />}
        {data && data.items.length === 0 && (
          <Empty title="Сегментов не найдено" />
        )}
        {data && data.items.length > 0 && (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>Сегмент</th>
                  <th>Владелец</th>
                  <th>Состояние</th>
                  <th className="num">k / n</th>
                  <th className="num">Живых</th>
                  <th className="num">Фрагментов</th>
                  <th className="num">Данные</th>
                  <th>Размещён</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((segment) => (
                  <tr key={`${segment.accountId}/${segment.segmentId}`}>
                    <td>
                      <Link
                        to={`/segments/${segment.accountId}/${segment.segmentId}`}
                        className="mono strong-link"
                      >
                        {segment.segmentId.slice(0, 12)}…
                      </Link>
                      <div className="subline">
                        <span className="muted">
                          размер фрагмента {formatBytes(segment.fragmentSize)}
                        </span>
                      </div>
                    </td>
                    <td>
                      {segment.login ? (
                        <Link to={`/users/${segment.accountId}`}>
                          {segment.login}
                        </Link>
                      ) : (
                        <CopyId value={segment.accountId} head={8} />
                      )}
                    </td>
                    <td>
                      <Badge
                        tone={
                          segment.state === 'ok'
                            ? 'good'
                            : segment.state === 'repair'
                              ? 'warn'
                              : 'neutral'
                        }
                      >
                        {statusLabel(segment.state)}
                      </Badge>
                    </td>
                    <td className="num">
                      {segment.k} / {segment.n}
                    </td>
                    <td
                      className={`num ${segment.live < segment.k ? 'bad-text' : ''}`}
                    >
                      {segment.live}
                    </td>
                    <td className="num">
                      {segment.storedFragments}
                      {segment.damagedFragments > 0 && (
                        <span className="bad-text">
                          {' '}
                          / {segment.damagedFragments} повреждено
                        </span>
                      )}
                    </td>
                    <td className="num">{formatBytes(segment.dataBytes)}</td>
                    <td>
                      {formatAgo(segment.allocatedAt)}
                      {segment.repairSince && (
                        <div className="subline warn-text">
                          ремонт с {formatAgo(segment.repairSince)}
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
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
