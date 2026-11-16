import { useEffect, useState } from 'react';
import { useFetch } from '../api';
import { BarChart } from '../components/charts';
import { Icon } from '../components/Icon';
import {
  Badge,
  Card,
  DownloadButton,
  Empty,
  ErrorBox,
  Loading,
  Pagination,
  SearchField,
  Select,
  Toolbar,
} from '../components/ui';
import {
  formatAgo,
  formatDateTime,
  formatNumber,
} from '../lib/format';
import { Link, useTitle } from '../lib/router';
import { useDebounced } from '../lib/useDebounced';
import type { CrashReport, CrashReportPage } from '../types';

export function Reports() {
  useTitle('Отчёты о сбоях');
  const [query, setQuery] = useState('');
  const [version, setVersion] = useState('');
  const [os, setOs] = useState('');
  const [days, setDays] = useState('30');
  const [page, setPage] = useState(1);
  const debounced = useDebounced(query);
  useEffect(() => setPage(1), [debounced, version, os, days]);
  const limit = 25;
  const path = `/api/reports?${new URLSearchParams({
    query: debounced,
    version,
    os,
    days,
    offset: String((page - 1) * limit),
    limit: String(limit),
  })}`;
  const { data, loading, error, reload } =
    useFetch<CrashReportPage>(path);

  return (
    <div className="page">
      <header className="page-head">
        <div>
          <h1>Отчёты о сбоях</h1>
          <p className="muted">
            Обезличенные отчёты приложений: версия, ОС, ошибка и стек после
            очистки от путей и ключей. Отправляются только с согласия
            пользователя.
          </p>
        </div>
        <div className="head-actions">
          <DownloadButton href="/api/export/reports.csv" label="CSV" />
          <button type="button" className="button" onClick={reload}>
            <Icon name="refresh" size={16} /> Обновить
          </button>
        </div>
      </header>

      {loading && !data && <Loading />}
      {error && <ErrorBox message={error} onRetry={reload} />}
      {data && (
        <div className="stat-grid">
          <div className="stat">
            <span className="stat-label">Всего отчётов</span>
            <strong className="stat-value">{formatNumber(data.summary.total)}</strong>
            <span className="stat-hint">за всё время хранения</span>
          </div>
          <div className="stat">
            <span className="stat-label">За 24 часа</span>
            <strong className="stat-value">{formatNumber(data.summary.last24h)}</strong>
            <span className="stat-hint">и {formatNumber(data.summary.last7d)} за 7 дней</span>
          </div>
          <div className="stat">
            <span className="stat-label">Версия</span>
            <strong className="stat-value">
              {data.summary.byVersion[0]?.name ?? '—'}
            </strong>
            <span className="stat-hint">
              {formatNumber(data.summary.byVersion[0]?.count ?? 0)} отчётов
            </span>
          </div>
          <div className="stat">
            <span className="stat-label">Система</span>
            <strong className="stat-value">
              {data.summary.byOs[0]?.name.split(' ')[0] ?? '—'}
            </strong>
            <span className="stat-hint">
              {formatNumber(data.summary.byOs[0]?.count ?? 0)} отчётов
            </span>
          </div>
        </div>
      )}

      {data && (
        <div className="grid-2">
          <Card title="По дням" subtitle="за 14 дней">
            <BarChart
              data={data.summary.byDay.map((day) => ({
                label: day.day.slice(5),
                value: day.count,
              }))}
              height={130}
            />
          </Card>
          <Card title="Частые ошибки" subtitle="первая строка, числа заменены на #">
            {data.summary.top.length === 0 ? (
              <Empty title="Ошибок нет" />
            ) : (
              <div className="rows">
                {data.summary.top.slice(0, 8).map((item) => (
                  <div className="row-line" key={item.name}>
                    <span className="ellipsis" title={item.name}>
                      {item.name}
                    </span>
                    <strong>{formatNumber(item.count)}</strong>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>
      )}

      <Card>
        <Toolbar
          actions={
            <Select
              value={days}
              onChange={setDays}
              options={[
                { value: '7', label: '7 дней' },
                { value: '30', label: '30 дней' },
                { value: '90', label: '90 дней' },
                { value: '0', label: 'всё время' },
              ]}
            />
          }
        >
          <SearchField
            value={query}
            onChange={setQuery}
            placeholder="Текст ошибки или стека"
          />
          <Select
            value={version}
            onChange={setVersion}
            options={[
              { value: '', label: 'все версии' },
              ...(data?.summary.byVersion ?? []).map((item) => ({
                value: item.name,
                label: item.name,
              })),
            ]}
          />
          <Select
            value={os}
            onChange={setOs}
            options={[
              { value: '', label: 'все системы' },
              ...(data?.summary.byOs ?? []).map((item) => ({
                value: item.name,
                label: item.name,
              })),
            ]}
          />
        </Toolbar>
        {data && data.items.length === 0 && (
          <Empty title="Отчётов не найдено">
            Пусто — это хорошо. Отчёты появляются только при сбоях и с
            согласия пользователя.
          </Empty>
        )}
        {data && data.items.length > 0 && (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>Получен</th>
                  <th>Ошибка</th>
                  <th>Версия</th>
                  <th>Система</th>
                  <th>Источник</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {data.items.map((report) => (
                  <tr key={report.id}>
                    <td title={formatDateTime(report.receivedAt)}>
                      {formatAgo(report.receivedAt)}
                    </td>
                    <td className="report-error-cell">
                      <Link to={`/reports/${report.id}`} className="strong-link">
                        {firstLine(report.error)}
                      </Link>
                      <div className="subline muted">
                        сбой {formatDateTime(report.at)}
                      </div>
                    </td>
                    <td>
                      <code>{report.version}</code>
                    </td>
                    <td>{report.os}</td>
                    <td>
                      <Badge tone="neutral">{report.source}</Badge>
                    </td>
                    <td>
                      <Link to={`/reports/${report.id}`} className="button small ghost">
                        Открыть <Icon name="chevron" size={13} />
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {data && (
          <Pagination
            page={page}
            total={data.total}
            limit={data.limit}
            onChange={setPage}
          />
        )}
      </Card>
    </div>
  );
}

function firstLine(text: string): string {
  return text.split('\n')[0] ?? text;
}

export function ReportDetail({ id }: { id: string }) {
  useTitle('Отчёт о сбое');
  const { data, loading, error, reload } = useFetch<CrashReport>(
    `/api/reports/${encodeURIComponent(id)}`,
  );
  return (
    <div className="page">
      <Link to="/reports" className="back-link">
        <Icon name="back" size={15} /> К отчётам
      </Link>
      {loading && !data && <Loading />}
      {error && <ErrorBox message={error} onRetry={reload} />}
      {data && (
        <>
          <header className="page-head">
            <div>
              <h1>Отчёт о сбое</h1>
              <p className="muted">
                {data.version} · {data.os} · получен{' '}
                {formatDateTime(data.receivedAt)}
              </p>
            </div>
            <button
              type="button"
              className="button"
              onClick={() => {
                void navigator.clipboard?.writeText(
                  `${data.error}\n\n${data.stack}`,
                );
              }}
            >
              <Icon name="copy" size={15} /> Скопировать
            </button>
          </header>
          <Card title="Ошибка">
            <pre className="code-block">{data.error}</pre>
          </Card>
          <Card title="Стек" subtitle="пути и секреты заменены на <path> и <secret>">
            <pre className="code-block small">{data.stack || 'стек пуст'}</pre>
          </Card>
          <Card title="Сведения">
            <dl className="kv-list">
              <div className="kv">
                <dt>ID</dt>
                <dd>
                  <code>{data.id}</code>
                </dd>
              </div>
              <div className="kv">
                <dt>Время сбоя</dt>
                <dd>{formatDateTime(data.at)}</dd>
              </div>
              <div className="kv">
                <dt>Получен</dt>
                <dd>{formatDateTime(data.receivedAt)}</dd>
              </div>
              <div className="kv">
                <dt>Источник</dt>
                <dd>{data.source}</dd>
              </div>
            </dl>
          </Card>
        </>
      )}
    </div>
  );
}
