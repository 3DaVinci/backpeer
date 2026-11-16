import { useState, type FormEvent } from 'react';
import { ApiError, login } from '../api';
import { Icon } from '../components/Icon';
import { LogoMark } from '../components/Logo';
import { useTitle } from '../lib/router';
import type { Session } from '../types';

export function Login({ onSuccess }: { onSuccess: (session: Session) => void }) {
  useTitle('Вход');
  const [user, setUser] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setLoading(true);
    try {
      onSuccess(await login(user.trim(), password));
    } catch (cause) {
      setError(
        cause instanceof ApiError ? cause.message : 'не удалось войти',
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-brand">
          <LogoMark />
          <div>
            <strong>Backpeer</strong>
            <span>панель оператора</span>
          </div>
        </div>
        <h1>Вход</h1>
        <p className="muted">
          Доступ только для операторов сети. Панель работает в режиме
          просмотра: данные не изменяются.
        </p>
        <form onSubmit={submit} className="form">
          <label>
            <span>Имя оператора</span>
            <input
              autoComplete="username"
              autoFocus
              required
              maxLength={64}
              value={user}
              onChange={(event) => setUser(event.target.value)}
            />
          </label>
          <label>
            <span>Пароль</span>
            <input
              type="password"
              autoComplete="current-password"
              required
              maxLength={1024}
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </label>
          {error && (
            <div className="notice notice-bad" role="alert">
              <Icon name="alert" size={16} />
              <span>{error}</span>
            </div>
          )}
          <button type="submit" className="button primary" disabled={loading}>
            {loading ? 'Вход…' : 'Войти'}
            {!loading && <Icon name="chevron" size={16} />}
          </button>
        </form>
        <p className="login-foot">
          Нет доступа? Операторов настраивает администратор сервера
          (<code>docs/ops/admin.md</code>).
        </p>
      </div>
      <div className="login-aside">
        <h2>Что внутри</h2>
        <ul>
          <li>учётные записи, устройства и узлы-хранители;</li>
          <li>балансы и журнал кредитов;</li>
          <li>состояние сегментов, аудиты и ремонт;</li>
          <li>трафик и relay;</li>
          <li>отчёты о сбоях приложений;</li>
          <li>журнал действий администратора.</li>
        </ul>
        <p className="muted">
          Все данные — метаданные координатора. Ключи, пароли и содержимое
          файлов панель не видит.
        </p>
      </div>
    </div>
  );
}
