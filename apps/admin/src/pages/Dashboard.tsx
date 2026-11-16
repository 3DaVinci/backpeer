import { useFetch } from '../api';
import { BarChart, LineChart, StackedBar } from '../components/charts';
import { Icon } from '../components/Icon';
import {
  Card,
  Empty,
  ErrorBox,
  Loading,
  StatCard,
} from '../components/ui';
import {
  countryName,
  formatAgo,
  formatBytes,
  formatCredits,
  formatDateTime,
  formatNumber,
  formatPercent,
  methodLabel,
} from '../lib/format';
import { Link, useTitle } from '../lib/router';
import type { Overview } from '../types';

const segmentColors: Record<string, string> = {
  pending: '#8b949e',
  ok: '#0f6b5c',
  repair: '#b7791f',
  unknown: '#b3261e',
};

const methodColors: Record<string, string> = {
  direct: '#0f6b5c',
  udp: '#1b66d1',
  relay: '#b7791f',
};

export function Dashboard() {
  useTitle('Обзор');
  const { data, loading, error, reload } = useFetch<Overview>('/api/overview');
  return (
    <div className="page">
      <header className="page-head">
        <div>
          <h1>Обзор сети</h1>
          <p className="muted">
            {data
              ? `Сводка на ${formatDateTime(data.generatedAt)}`
              : 'Сводка координатора и принятых отчётов'}
          </p>
        </div>
        <button type="button" className="button" onClick={reload}>
          <Icon name="refresh" size={16} /> Обновить
        </button>
      </header>
      {loading && !data && <Loading />}
      {error && <ErrorBox message={error} onRetry={reload} />}
      {data && <OverviewBody data={data} />}
    </div>
  );
}

function OverviewBody({ data }: { data: Overview }) {
  const { stats } = data;
  const onlineShare = stats.nodes > 0 ? stats.nodesOnline / stats.nodes : 0;
  const segmentTotal = Object.values(stats.segments).reduce((a, b) => a + b, 0);
  const trafficTotal = Object.values(data.traffic).reduce(
    (sum, item) => sum + item.bytes,
    0,
  );
  const segmentParts = [
    { label: 'здоровы', value: stats.segments.ok ?? 0, color: segmentColors.ok! },
    { label: 'ремонт', value: stats.segments.repair ?? 0, color: segmentColors.repair! },
    { label: 'размещаются', value: stats.segments.pending ?? 0, color: segmentColors.pending! },
  ];
  return (
    <>
      <div className="stat-grid">
        <StatCard
          label="Учётные записи"
          value={formatNumber(stats.accounts)}
          hint={`${formatNumber(stats.accountsBlocked)} заблокировано · ${formatNumber(stats.devicesActive)} устройств`}
        />
        <StatCard
          label="Хранители в сети"
          value={`${formatNumber(stats.nodesOnline)} / ${formatNumber(stats.nodes)}`}
          hint={`${formatPercent(onlineShare)} · ${formatBytes(stats.capacityBytes)} ёмкости`}
          tone={onlineShare < 0.5 ? 'warn' : 'good'}
        />
        <StatCard
          label="Данные клиентов"
          value={formatBytes(data.dataBytes)}
          hint={`${formatNumber(segmentTotal)} сегментов · ${formatNumber(data.objectsCount)} объектов`}
        />
        <StatCard
          label="Баланс сети"
          value={formatCredits(data.economy.balanceMc)}
          hint={`${formatNumber(data.economy.negativeAccounts)} в долге · грант ${formatCredits(data.economy.starterCredits * 1_000_000)}`}
          tone={data.economy.negativeAccounts > 0 ? 'warn' : 'good'}
        />
        <StatCard
          label="Очередь ремонта"
          value={formatNumber(data.repair.queue)}
          hint={`${formatNumber(data.repair.running)} заданий · минимум ${data.repair.minLive ?? '—'} живых`}
          tone={data.repair.queue > 0 ? 'warn' : 'good'}
        />
        <StatCard
          label="Отчёты о сбоях"
          value={formatNumber(data.reports.last24h)}
          hint={`за 24 ч · всего ${formatNumber(data.reports.total)}`}
          tone={data.reports.last24h > 0 ? 'warn' : 'default'}
        />
      </div>

      <div className="grid-2">
        <Card title="Рост сети" subtitle="новые учётные записи и хранители за 14 дней">
          <LineChart
            series={[
              {
                name: 'учётные записи',
                color: '#0f6b5c',
                points: data.activity.accounts,
              },
              {
                name: 'хранители',
                color: '#1b66d1',
                points: data.activity.nodes,
              },
            ]}
          />
        </Card>
        <Card title="Здоровье данных" subtitle={`${formatNumber(segmentTotal)} сегментов`}>
          <StackedBar parts={segmentParts} />
          <div className="mini-grid">
            <div>
              <span>Живых фрагментов</span>
              <strong>{formatNumber(data.storedFragments)}</strong>
            </div>
            <div>
              <span>Повреждено</span>
              <strong className={data.damagedFragments > 0 ? 'bad-text' : ''}>
                {formatNumber(data.damagedFragments)}
              </strong>
            </div>
            <div>
              <span>Проверено аудитом за 24 ч</span>
              <strong>
                {formatNumber(data.audits.passed24h)} /{' '}
                {formatNumber(data.audits.passed24h + data.audits.failed24h)}
              </strong>
            </div>
            <div>
              <span>Средний ответ</span>
              <strong>
                {data.audits.latencyMs === null
                  ? '—'
                  : `${formatNumber(data.audits.latencyMs)} мс`}
              </strong>
            </div>
          </div>
        </Card>
      </div>

      <div className="grid-2">
        <Card
          title="Трафик за 24 часа"
          subtitle={`${formatBytes(trafficTotal)} по отчётам клиентов и узлов`}
        >
          {Object.keys(data.traffic).length === 0 ? (
            <Empty title="Отчётов о трафике пока нет" />
          ) : (
            <BarChart
              data={Object.entries(data.traffic).map(([method, item]) => ({
                label: methodLabel(method),
                value: item.bytes,
              }))}
              format={(value) => formatBytes(value)}
            />
          )}
          <div className="legend legend-wrap">
            {Object.entries(data.traffic).map(([method, item]) => (
              <span key={method}>
                <i style={{ background: methodColors[method] ?? '#8b949e' }} />
                {methodLabel(method)}: {formatNumber(item.connections)} соединений,{' '}
                {formatNumber(item.accounts)} учётных записей
              </span>
            ))}
          </div>
        </Card>
        <Card title="Хранители" subtitle="состояние реестра">
          <div className="mini-grid">
            <div>
              <span>не в сети</span>
              <strong>{formatNumber(stats.nodes - stats.nodesOnline)}</strong>
            </div>
            <div>
              <span>исключены</span>
              <strong>{formatNumber(stats.nodesExcluded)}</strong>
            </div>
            <div>
              <span>испытательный срок</span>
              <strong>{formatNumber(stats.nodesOnProbation)}</strong>
            </div>
            <div>
              <span>свободно на дисках</span>
              <strong>{formatBytes(data.nodesFreeBytes)}</strong>
            </div>
            <div>
              <span>занято фрагментами</span>
              <strong>{formatBytes(data.nodesUsedBytes)}</strong>
            </div>
            <div>
              <span>выделено</span>
              <strong>{formatBytes(data.nodesAssignedBytes)}</strong>
            </div>
          </div>
          <div className="version-list">
            {data.versions.slice(0, 5).map((version) => (
              <div key={version.name} className="version-row">
                <code>{version.name}</code>
                <span>{formatNumber(version.count)}</span>
              </div>
            ))}
          </div>
          <p className="muted small-text">
            <Link to="/nodes">Открыть реестр хранителей →</Link>
          </p>
        </Card>
      </div>

      <div className="grid-2">
        <Card
          title="Последние сбои"
          subtitle="по отчётам приложений (без имени пользователя)"
          actions={<Link to="/reports">все отчёты →</Link>}
        >
          {!data.recentReports || data.recentReports.length === 0 ? (
            <Empty title="Отчётов о сбоях нет">
              Приложения присылают их только с согласия пользователя.
            </Empty>
          ) : (
            <ul className="report-list">
              {data.recentReports.map((report) => (
                <li key={report.id}>
                  <Link to={`/reports/${report.id}`} className="report-line">
                    <span className="report-error">{firstLine(report.error)}</span>
                    <span className="report-meta">
                      {report.version} · {report.os} · {formatAgo(report.receivedAt)}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
          {data.reports.top.length > 0 && (
            <div className="top-list">
              <h3>Частые ошибки</h3>
              {data.reports.top.slice(0, 5).map((item) => (
                <div key={item.name} className="top-row">
                  <span title={item.name}>{item.name}</span>
                  <strong>{formatNumber(item.count)}</strong>
                </div>
              ))}
            </div>
          )}
        </Card>
        <Card
          title="Последние действия оператора"
          subtitle="журнал только на добавление"
          actions={<Link to="/journal">весь журнал →</Link>}
        >
          {data.journal.length === 0 ? (
            <Empty title="Записей нет" />
          ) : (
            <ul className="timeline">
              {data.journal.map((entry) => (
                <li key={entry.id}>
                  <div>
                    <strong>{entry.command}</strong>
                    <span className="muted"> · {entry.osUser}</span>
                  </div>
                  <div className="muted small-text">
                    {formatDateTime(entry.at)} · {entry.result}
                    {entry.reason ? ` · ${entry.reason}` : ''}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <div className="grid-2">
        <Card title="География" subtitle="страны хранителей по geoip">
          {data.countries.length === 0 ? (
            <Empty title="Нет данных geoip" />
          ) : (
            <BarChart
              data={data.countries.map((item) => ({
                label: countryName(item.code),
                value: item.count,
              }))}
              height={150}
            />
          )}
        </Card>
        <Card title="Экономика" subtitle="бартер 2,5 : 1, кредиты за занятые фрагменты">
          <div className="mini-grid">
            <div>
              <span>сумма балансов</span>
              <strong>{formatCredits(data.economy.balanceMc)}</strong>
            </div>
            <div>
              <span>начислено</span>
              <strong>{formatCredits(data.economy.earnedMc)}</strong>
            </div>
            <div>
              <span>списано</span>
              <strong>{formatCredits(data.economy.spentMc)}</strong>
            </div>
            <div>
              <span>льготный период</span>
              <strong>{data.economy.graceDays} дн.</strong>
            </div>
            <div>
              <span>запрещены новые данные</span>
              <strong>{formatNumber(data.economy.blockedAccounts)}</strong>
            </div>
            <div>
              <span>отчётов за 7 дней</span>
              <strong>{formatNumber(data.reports.last7d)}</strong>
            </div>
          </div>
          <p className="muted small-text">
            <Link to="/economy">Открыть экономику →</Link>
          </p>
        </Card>
      </div>
    </>
  );
}

function firstLine(text: string): string {
  return text.split('\n')[0] ?? text;
}
