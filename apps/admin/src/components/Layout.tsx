import type { ReactNode } from 'react';
import { Icon } from './Icon';
import { LogoMark } from './Logo';
import { Link, navigate } from '../lib/router';

const nav = [
  { href: '/', label: 'Обзор', icon: 'dashboard' as const },
  { href: '/users', label: 'Пользователи', icon: 'users' as const },
  { href: '/nodes', label: 'Хранители', icon: 'nodes' as const },
  { href: '/network', label: 'Сеть и данные', icon: 'network' as const },
  { href: '/segments', label: 'Сегменты', icon: 'nodes' as const },
  { href: '/economy', label: 'Экономика', icon: 'economy' as const },
  { href: '/reports', label: 'Отчёты о сбоях', icon: 'bug' as const },
  { href: '/journal', label: 'Журнал', icon: 'journal' as const },
  { href: '/system', label: 'Система', icon: 'system' as const },
];

function sectionTitle(path: string): string {
  if (path.startsWith('/users/')) return 'Учётная запись';
  if (path.startsWith('/users')) return 'Пользователи';
  if (path.startsWith('/nodes/')) return 'Хранитель';
  if (path.startsWith('/nodes')) return 'Хранители';
  if (path.startsWith('/segments/')) return 'Сегмент';
  if (path.startsWith('/segments')) return 'Сегменты';
  if (path.startsWith('/network')) return 'Сеть и данные';
  if (path.startsWith('/economy')) return 'Экономика';
  if (path.startsWith('/reports/')) return 'Отчёт о сбое';
  if (path.startsWith('/reports')) return 'Отчёты о сбоях';
  if (path.startsWith('/journal')) return 'Журнал оператора';
  if (path.startsWith('/system')) return 'Система';
  return 'Обзор';
}

export function Layout({
  path,
  user,
  onLogout,
  children,
}: {
  path: string;
  user: string;
  onLogout: () => void;
  children: ReactNode;
}) {
  return (
    <div className="shell">
      <aside className="sidebar">
        <Link to="/" className="brand" aria-label="Backpeer, на главную">
          <LogoMark />
          <span>
            <strong>Backpeer</strong>
            <small>панель оператора</small>
          </span>
        </Link>
        <div className="readonly-pill">
          <Icon name="eye" size={14} /> только просмотр
        </div>
        <nav className="nav" aria-label="Разделы">
          {nav.map((item) => {
            const active =
              item.href === '/'
                ? path === '/'
                : path === item.href || path.startsWith(`${item.href}/`);
            return (
              <Link
                key={item.href}
                to={item.href}
                className={active ? 'nav-item active' : 'nav-item'}
              >
                <Icon name={item.icon} size={17} />
                {item.label}
              </Link>
            );
          })}
        </nav>
        <div className="sidebar-foot">
          <span className="muted">Изменения — только через</span>
          <code>coordinator admin</code>
        </div>
      </aside>
      <div className="main">
        <header className="topbar">
          <div className="topbar-title">
            <span className="crumbs">
              <Link to="/">Панель</Link>
              <Icon name="chevron" size={13} />
              <span>{sectionTitle(path)}</span>
            </span>
          </div>
          <div className="topbar-actions">
            <span className="user" title="Оператор">
              <Icon name="users" size={15} /> {user}
            </span>
            <button
              type="button"
              className="button small ghost"
              onClick={() => {
                onLogout();
                navigate('/');
              }}
            >
              <Icon name="logout" size={15} /> Выйти
            </button>
          </div>
        </header>
        <main id="main" className="content" tabIndex={-1}>
          {children}
        </main>
      </div>
    </div>
  );
}
