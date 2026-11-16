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
  formatCredits,
  formatDateTime,
  formatNumber,
  ledgerKind,
} from '../lib/format';
import { Link, useTitle } from '../lib/router';
import type { Economy } from '../types';

export function EconomyPage() {
  useTitle('Экономика');
  const [days, setDays] = useState('30');
  const { data, loading, error, reload } = useFetch<Economy>(
    `/api/economy?days=${days}`,
  );
  return (
    <div className="page">
      <header className="page-head">
        <div>
          <h1>Экономика</h1>
          <p className="muted">
            Бартерная квота, кредиты за занятые фрагменты, балансы и журнал
            проводок. 1 CR = 1 000 000 мк.
          </p>
        </div>
        <div className="head-actions">
          <Select
            value={days}
            onChange={setDays}
            options={[
              { value: '7', label: '7 дней' },
              { value: '30', label: '30 дней' },
              { value: '90', label: '90 дней' },
              { value: '365', label: 'год' },
            ]}
          />
          <button type="button" className="button" onClick={reload}>
            <Icon name="refresh" size={16} /> Обновить
          </button>
        </div>
      </header>
      {loading && !data && <Loading />}
      {error && <ErrorBox message={error} onRetry={reload} />}
      {data && <Body data={data} />}
    </div>
  );
}

function Body({ data }: { data: Economy }) {
  const { summary, policy } = data;
  const netColor = summary.totalMc < 0 ? '#b3261e' : '#0f6b5c';
  return (
    <>
      <div className="stat-grid">
        <StatCard
          label="Сумма балансов"
          value={formatCredits(summary.totalMc)}
          hint={`${formatNumber(summary.accounts)} учётных записей`}
          tone={summary.totalMc < 0 ? 'warn' : 'good'}
        />
        <StatCard
          label="Положительный баланс"
          value={formatCredits(summary.positiveMc)}
          hint={`${formatNumber(summary.positiveAccounts)} учётных записей`}
          tone="good"
        />
        <StatCard
          label="Долг"
          value={formatCredits(summary.negativeMc)}
          hint={`${formatNumber(summary.negativeAccounts)} учётных записей`}
          tone={summary.negativeAccounts > 0 ? 'warn' : 'default'}
        />
        <StatCard
          label="Запрещены новые данные"
          value={formatNumber(summary.blockedAccounts)}
          hint={`долг дольше ${policy.graceDays} дн.`}
          tone={summary.blockedAccounts > 0 ? 'bad' : 'good'}
        />
      </div>

      <div className="grid-2">
        <Card title="Движение кредитов" subtitle={`за ${data.days} дней`}>
          {data.daily.length === 0 ? (
            <Empty title="Проводок нет" />
          ) : (
            <BarChart
              data={data.daily.map((day) => ({
                label: day.day.slice(5),
                value: day.earnedMc + day.spentMc,
              }))}
              format={(value) => formatCredits(value)}
              height={150}
            />
          )}
          <StackedBar
            parts={[
              {
                label: 'начислено',
                value: data.daily.reduce((sum, day) => sum + day.earnedMc, 0),
                color: '#0f6b5c',
              },
              {
                label: 'списано',
                value: data.daily.reduce((sum, day) => sum + day.spentMc, 0),
                color: '#b3261e',
              },
            ]}
            format={(value) => formatCredits(value)}
          />
        </Card>

        <Card title="Тарифы" subtitle="совпадают с economy.* координатора">
          <div className="mini-grid">
            <div>
              <span>хранение 1 ТБ·мес</span>
              <strong>{formatCredits(policy.dataCreditsPerTbMonth * 1_000_000)}</strong>
            </div>
            <div>
              <span>хранителю за 1 ТБ·мес</span>
              <strong>{formatCredits(policy.storeCreditsPerTbMonth * 1_000_000)}</strong>
            </div>
            <div>
              <span>бартер ёмкость : данные</span>
              <strong>{policy.barterRatio.toFixed(1)} : 1</strong>
            </div>
            <div>
              <span>стартовый грант</span>
              <strong>{formatCredits(policy.starterCredits * 1_000_000)}</strong>
            </div>
            <div>
              <span>льготный период</span>
              <strong>{policy.graceDays} дн.</strong>
            </div>
            <div>
              <span>сумма балансов</span>
              <strong style={{ color: netColor }}>{formatCredits(summary.totalMc)}</strong>
            </div>
          </div>
          <p className="muted small-text">
            Кредиты начисляются только за занятые фрагменты; за
            зарезервированное место — нет. Долг не удаляет данные.
          </p>
        </Card>
      </div>

      <div className="grid-2">
        <Card title="Самые большие балансы">
          {data.topPositive.length === 0 ? (
            <Empty title="Положительных балансов нет" />
          ) : (
            <div className="rows">
              {data.topPositive.map((account) => (
                <div className="row-line" key={account.accountId}>
                  <Link to={`/users/${account.accountId}`}>
                    {account.login ?? account.accountId.slice(0, 12)}
                  </Link>
                  <strong className="good-text">
                    {formatCredits(account.balanceMc)}
                  </strong>
                </div>
              ))}
            </div>
          )}
        </Card>
        <Card title="Самые большие долги" subtitle={`льготный период ${policy.graceDays} дн.`}>
          {data.topNegative.length === 0 ? (
            <Empty title="Долгов нет" />
          ) : (
            <div className="rows">
              {data.topNegative.map((account) => (
                <div className="row-line" key={account.accountId}>
                  <Link to={`/users/${account.accountId}`}>
                    {account.login ?? account.accountId.slice(0, 12)}
                  </Link>
                  <span className="bad-text">{formatCredits(account.balanceMc)}</span>
                  <span className="muted small-text">
                    с {formatDateTime(account.negativeSince)}
                  </span>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      <Card
        title="Журнал проводок"
        subtitle={`последние ${data.ledger.length} за ${data.days} дней`}
      >
        {data.ledger.length === 0 ? (
          <Empty title="Проводок нет" />
        ) : (
          <div className="table-wrap">
            <table className="table compact">
              <thead>
                <tr>
                  <th>Когда</th>
                  <th>Учётная запись</th>
                  <th>Операция</th>
                  <th className="num">Сумма</th>
                  <th>День</th>
                  <th>Примечание</th>
                </tr>
              </thead>
              <tbody>
                {data.ledger.map((entry, index) => (
                  <tr key={`${entry.accountId}-${entry.createdAt}-${index}`}>
                    <td>{formatAgo(entry.createdAt)}</td>
                    <td>
                      <Link to={`/users/${entry.accountId}`}>
                        {entry.login ?? entry.accountId.slice(0, 10)}
                      </Link>
                    </td>
                    <td>
                      <Badge
                        tone={
                          entry.amountMc > 0
                            ? 'good'
                            : entry.kind === 'penalty'
                              ? 'bad'
                              : 'neutral'
                        }
                      >
                        {ledgerKind(entry.kind)}
                      </Badge>
                    </td>
                    <td
                      className={`num ${entry.amountMc < 0 ? 'bad-text' : 'good-text'}`}
                    >
                      {entry.amountMc > 0 ? '+' : ''}
                      {formatCredits(entry.amountMc)}
                    </td>
                    <td>{entry.day}</td>
                    <td className="muted">{entry.note || entry.ref}</td>
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
