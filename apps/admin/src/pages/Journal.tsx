import { useEffect, useState } from 'react';
import { useFetch } from '../api';
import { Icon } from '../components/Icon';
import {
  Badge,
  Card,
  Empty,
  ErrorBox,
  Loading,
  Pagination,
  SearchField,
  Toolbar,
} from '../components/ui';
import { formatDateTime, formatNumber } from '../lib/format';
import { useTitle } from '../lib/router';
import { useDebounced } from '../lib/useDebounced';
import type { JournalEntry, Page } from '../types';

export function Journal() {
  useTitle('Журнал оператора');
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);
  const debounced = useDebounced(query);
  useEffect(() => setPage(1), [debounced]);
  const { data, loading, error, reload } = useFetch<Page<JournalEntry>>(
    `/api/journal?${new URLSearchParams({
      query: debounced,
      page: String(page),
      limit: '50',
    })}`,
  );
  return (
    <div className="page">
      <header className="page-head">
        <div>
          <h1>Журнал оператора</h1>
          <p className="muted">
            Действия <code>coordinator admin</code>: кто, что, когда и с какой
            причиной. Таблица только на добавление; панель её не меняет.
          </p>
        </div>
        <button type="button" className="button" onClick={reload}>
          <Icon name="refresh" size={16} /> Обновить
        </button>
      </header>
      <Card>
        <Toolbar>
          <SearchField
            value={query}
            onChange={setQuery}
            placeholder="Команда, оператор, причина, результат"
          />
        </Toolbar>
        {loading && !data && <Loading />}
        {error && <ErrorBox message={error} onRetry={reload} />}
        {data && data.items.length === 0 && (
          <Empty title="Записей нет">
            Изменяющие команды администратора появятся здесь.
          </Empty>
        )}
        {data && data.items.length > 0 && (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>Когда</th>
                  <th>Оператор</th>
                  <th>Команда</th>
                  <th>Аргументы</th>
                  <th>Причина</th>
                  <th>Результат</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((entry) => (
                  <tr key={entry.id}>
                    <td>{formatDateTime(entry.at)}</td>
                    <td>
                      <div>{entry.osUser}</div>
                      <div className="subline muted">{entry.dbUser}</div>
                    </td>
                    <td>
                      <code>{entry.command}</code>
                    </td>
                    <td>
                      <details className="details">
                        <summary>JSON</summary>
                        <pre className="code-block small">
                          {JSON.stringify(entry.arguments, null, 2)}
                        </pre>
                      </details>
                    </td>
                    <td>{entry.reason ?? '—'}</td>
                    <td>
                      <Badge
                        tone={
                          entry.result === 'ok'
                            ? 'good'
                            : entry.result === 'unchanged'
                              ? 'neutral'
                              : 'bad'
                        }
                      >
                        {entry.result}
                      </Badge>
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
      <p className="muted small-text">
        Записей: {data ? formatNumber(data.total) : '—'}. Копия журнала уходит в
        системный журнал (<code>journalctl -t fs-coordinator-admin</code>).
      </p>
    </div>
  );
}
