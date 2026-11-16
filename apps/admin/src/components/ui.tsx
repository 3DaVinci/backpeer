import {
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { Icon } from './Icon';

export function Card({
  title,
  subtitle,
  actions,
  children,
  className = '',
}: {
  title?: ReactNode;
  subtitle?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={`card ${className}`}>
      {(title || actions) && (
        <header className="card-head">
          <div>
            {title && <h2 className="card-title">{title}</h2>}
            {subtitle && <p className="card-subtitle">{subtitle}</p>}
          </div>
          {actions && <div className="card-actions">{actions}</div>}
        </header>
      )}
      {children}
    </section>
  );
}

export function StatCard({
  label,
  value,
  hint,
  tone = 'default',
  onClick,
}: {
  label: string;
  value: ReactNode;
  hint?: ReactNode;
  tone?: 'default' | 'good' | 'warn' | 'bad';
  onClick?: () => void;
}) {
  const body = (
    <>
      <span className="stat-label">{label}</span>
      <strong className="stat-value">{value}</strong>
      {hint && <span className="stat-hint">{hint}</span>}
    </>
  );
  if (onClick) {
    return (
      <button type="button" className={`stat stat-${tone} stat-button`} onClick={onClick}>
        {body}
      </button>
    );
  }
  return <div className={`stat stat-${tone}`}>{body}</div>;
}

export function Badge({
  tone = 'neutral',
  children,
  title,
}: {
  tone?: 'neutral' | 'good' | 'warn' | 'bad' | 'info';
  children: ReactNode;
  title?: string;
}) {
  return (
    <span className={`badge badge-${tone}`} title={title}>
      {children}
    </span>
  );
}

export function Dot({ tone }: { tone: 'good' | 'warn' | 'bad' | 'neutral' }) {
  return <span className={`dot dot-${tone}`} aria-hidden="true" />;
}

export function ErrorBox({
  message,
  onRetry,
}: {
  message: string;
  onRetry?: () => void;
}) {
  return (
    <div className="notice notice-bad" role="alert">
      <Icon name="alert" />
      <div>
        <strong>Не удалось загрузить</strong>
        <p>{message}</p>
      </div>
      {onRetry && (
        <button type="button" className="button small" onClick={onRetry}>
          Повторить
        </button>
      )}
    </div>
  );
}

export function InfoBox({ children }: { children: ReactNode }) {
  return <div className="notice notice-info">{children}</div>;
}

export function Loading({ label = 'Загрузка…' }: { label?: string }) {
  return (
    <div className="loading" role="status">
      <span className="spinner" />
      {label}
    </div>
  );
}

export function Empty({
  title,
  children,
}: {
  title: string;
  children?: ReactNode;
}) {
  return (
    <div className="empty">
      <strong>{title}</strong>
      {children && <p>{children}</p>}
    </div>
  );
}

export function CopyId({
  value,
  head = 10,
  className = 'mono',
}: {
  value: string;
  head?: number;
  className?: string;
}) {
  const [copied, setCopied] = useState(false);
  useTimeout(() => setCopied(false), copied ? 1200 : null);
  const short =
    value.length <= head + 6 ? value : `${value.slice(0, head)}…${value.slice(-4)}`;
  return (
    <button
      type="button"
      className={`copy-id ${className}`}
      title={`${value}\nНажмите, чтобы скопировать`}
      onClick={(event) => {
        event.stopPropagation();
        void navigator.clipboard
          ?.writeText(value)
          .then(() => setCopied(true))
          .catch(() => undefined);
      }}
    >
      <span>{short}</span>
      <Icon name={copied ? 'check' : 'copy'} size={13} />
    </button>
  );
}

function useTimeout(fn: () => void, delay: number | null): void {
  const ref = useRef(fn);
  ref.current = fn;
  useEffect(() => {
    if (delay === null) return;
    const timer = window.setTimeout(() => ref.current(), delay);
    return () => window.clearTimeout(timer);
  }, [delay]);
}

export function ProgressBar({
  value,
  max,
  tone = 'accent',
  label,
}: {
  value: number;
  max: number;
  tone?: 'accent' | 'warn' | 'bad';
  label?: string;
}) {
  const ratio = max > 0 ? Math.max(0, Math.min(1, value / max)) : 0;
  return (
    <div
      className={`progress progress-${tone}`}
      role="progressbar"
      aria-valuemin={0}
      aria-valuemax={max}
      aria-valuenow={value}
      aria-label={label}
    >
      <span style={{ width: `${ratio * 100}%` }} />
    </div>
  );
}

export function Pagination({
  page,
  total,
  limit,
  onChange,
}: {
  page: number;
  total: number;
  limit: number;
  onChange: (page: number) => void;
}) {
  const pages = Math.max(1, Math.ceil(total / limit));
  if (pages <= 1) return null;
  return (
    <nav className="pagination" aria-label="Страницы">
      <button
        type="button"
        className="button small"
        disabled={page <= 1}
        onClick={() => onChange(page - 1)}
      >
        <Icon name="back" size={14} /> Назад
      </button>
      <span>
        Стр. {page} из {pages} · {total}
      </span>
      <button
        type="button"
        className="button small"
        disabled={page >= pages}
        onClick={() => onChange(page + 1)}
      >
        Вперёд <Icon name="chevron" size={14} />
      </button>
    </nav>
  );
}

export function SearchField({
  value,
  onChange,
  placeholder = 'Поиск',
}: {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
}) {
  return (
    <label className="search">
      <Icon name="search" size={16} />
      <input
        type="search"
        value={value}
        placeholder={placeholder}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}

export function Select({
  value,
  onChange,
  options,
  label,
}: {
  value: string;
  onChange: (value: string) => void;
  options: { value: string; label: string }[];
  label?: string;
}) {
  return (
    <label className="select">
      {label && <span>{label}</span>}
      <select value={value} onChange={(event) => onChange(event.target.value)}>
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  );
}

export function Tabs({
  value,
  onChange,
  options,
}: {
  value: string;
  onChange: (value: string) => void;
  options: { value: string; label: string; count?: number }[];
}) {
  return (
    <div className="tabs" role="tablist">
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          role="tab"
          aria-selected={value === option.value}
          className={value === option.value ? 'active' : ''}
          onClick={() => onChange(option.value)}
        >
          {option.label}
          {option.count !== undefined && <span>{option.count}</span>}
        </button>
      ))}
    </div>
  );
}

export function KeyValue({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <div className="kv">
      <dt>{label}</dt>
      <dd>{children}</dd>
    </div>
  );
}

export function Toolbar({
  children,
  actions,
}: {
  children: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <div className="toolbar">
      <div className="toolbar-main">{children}</div>
      {actions && <div className="toolbar-actions">{actions}</div>}
    </div>
  );
}

export function DownloadButton({ href, label = 'CSV' }: { href: string; label?: string }) {
  return (
    <a className="button small" href={href} download>
      <Icon name="download" size={14} /> {label}
    </a>
  );
}
