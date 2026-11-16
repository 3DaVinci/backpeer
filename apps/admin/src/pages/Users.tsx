import { useEffect, useState } from 'react';
import { useFetch } from '../api';
import { Icon } from '../components/Icon';
import {
  Badge,
  Card,
  CopyId,
  DownloadButton,
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
  formatCredits,
  formatDate,
  formatNumber,
} from '../lib/format';
import { Link, useTitle } from '../lib/router';
import { useDebounced } from '../lib/useDebounced';
import type { AccountSummary, Page } from '../types';

const filters = [
  { value: 'all', label: 'Все' },
  { value: 'blocked', label: 'Заблокированные' },
  { value: 'debt', label: 'С долгом' },
  { value: 'keepers', label: 'С хранителями' },
  { value: 'clients', label: 'С бэкапами' },
  { value: 'active', label: 'Активные' },
  { value: 'inactive', label: 'Неактивные' },
];

export function Users() {
  useTitle('Пользователи');
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState('all');
  const [sort, setSort] = useState('created_desc');
  const [page, setPage] = useState(1);
  const debounced = useDebounced(query);
  useEffect(() => setPage(1), [debounced, filter, sort]);
  const path = `/api/users?${new URLSearchParams({
    query: debounced,
    filter,
    sort,
    page: String(page),
    limit: '25',
  })}`;
  const { data, loading, error, reload } =
    useFetch<Page<AccountSummary>>(path);

  return (
    <div className="page">
      <header className="page-head">
        <div>
          <h1>Пользователи</h1>
          <p className="muted">
            Учётные записи координатора: устройства, хранители, объём и баланс.
            Ключи и содержимое файлов недоступны.
          </p>
        </div>
        <div className="head-actions">
          <DownloadButton href="/api/export/users.csv" label="CSV" />
          <button type="button" className="button" onClick={reload}>
            <Icon name="refresh" size={16} /> Обновить
          </button>
        </div>
      </header>

      <Card>
        <Toolbar
          actions={
            <Select
              value={sort}
              onChange={setSort}
              options={[
                { value: 'created_desc', label: 'сначала новые' },
                { value: 'created_asc', label: 'сначала старые' },
                { value: 'login', label: 'по имени' },
                { value: 'storage', label: 'по объёму' },
                { value: 'balance', label: 'по балансу ↑' },
                { value: 'balance_desc', label: 'по балансу ↓' },
                { value: 'activity', label: 'по активности' },
                { value: 'nodes', label: 'по числу узлов' },
              ]}
            />
          }
        >
          <SearchField
            value={query}
            onChange={setQuery}
            placeholder="Имя для входа или account_id"
          />
          <Tabs value={filter} onChange={setFilter} options={filters} />
        </Toolbar>

        {loading && !data && <Loading />}
        {error && <ErrorBox message={error} onRetry={reload} />}
        {data && data.items.length === 0 && (
          <Empty title="Ничего не найдено">
            Измените запрос или фильтр.
          </Empty>
        )}
        {data && data.items.length > 0 && (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>Учётная запись</th>
                  <th>Статус</th>
                  <th className="num">Устройства</th>
                  <th className="num">Узлы</th>
                  <th className="num">Бэкапы</th>
                  <th className="num">Баланс</th>
                  <th>Активность</th>
                  <th>Создана</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((account) => (
                  <tr key={account.accountId}>
                    <td>
                      <Link to={`/users/${account.accountId}`} className="strong-link">
                        {account.login ?? 'без имени'}
                      </Link>
                      <div className="subline">
                        <CopyId value={account.accountId} head={8} />
                      </div>
                    </td>
                    <td>
                      {account.blockedAt ? (
                        <Badge tone="bad" title={account.blockedReason ?? ''}>
                          заблокирована
                        </Badge>
                      ) : account.negativeSince ? (
                        <Badge tone="warn">в долге</Badge>
                      ) : (
                        <Badge tone="good">активна</Badge>
                      )}
                    </td>
                    <td className="num">{formatNumber(account.devicesActive)}</td>
                    <td className="num">
                      {formatNumber(account.nodesActive)}
                      <span className="muted">
                        {' '}
                        / {formatNumber(account.nodesOnline)} online
                      </span>
                    </td>
                    <td className="num">{formatNumber(account.segmentsActive)}</td>
                    <td
                      className={`num ${account.balanceMc < 0 ? 'bad-text' : ''}`}
                    >
                      {formatCredits(account.balanceMc)}
                    </td>
                    <td>{formatAgo(account.lastActivityAt)}</td>
                    <td>{formatDate(account.createdAt)}</td>
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

      <p className="muted small-text">
        Блокировка и разблокировка выполняются командой{' '}
        <code>coordinator admin account block|unblock</code> с причиной и
        журналом. Панель ничего не меняет.
      </p>
    </div>
  );
}
