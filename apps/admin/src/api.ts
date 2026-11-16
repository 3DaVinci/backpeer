import { useCallback, useEffect, useState } from 'react';
import type { Session } from './types';

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

export class UnauthorizedError extends ApiError {
  constructor() {
    super(401, 'нужен вход');
    this.name = 'UnauthorizedError';
  }
}

let unauthorizedHandler: (() => void) | null = null;

export function setUnauthorizedHandler(handler: (() => void) | null): void {
  unauthorizedHandler = handler;
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set('X-Requested-With', 'BackpeerAdmin');
  if (init.body !== undefined && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }
  const response = await fetch(path, {
    ...init,
    credentials: 'same-origin',
    headers,
  });
  const text = await response.text();
  let body: unknown = null;
  if (text) {
    try {
      body = JSON.parse(text) as unknown;
    } catch {
      body = null;
    }
  }
  if (response.status === 401) {
    unauthorizedHandler?.();
    throw new UnauthorizedError();
  }
  if (!response.ok) {
    const message =
      body !== null &&
      typeof body === 'object' &&
      'error' in body &&
      typeof (body as { error: unknown }).error === 'string'
        ? (body as { error: string }).error
        : `HTTP ${response.status}`;
    throw new ApiError(response.status, message);
  }
  return body as T;
}

export async function login(
  user: string,
  password: string,
): Promise<Session> {
  return request<Session>('/api/login', {
    method: 'POST',
    body: JSON.stringify({ user, password }),
  });
}

export async function logout(): Promise<void> {
  await request<{ ok: boolean }>('/api/logout', { method: 'POST' });
}

export async function currentSession(): Promise<Session | null> {
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch('/api/session', {
      credentials: 'same-origin',
      headers: { 'X-Requested-With': 'BackpeerAdmin' },
      signal: controller.signal,
    });
    if (response.status === 401) return null;
    if (!response.ok) {
      throw new ApiError(response.status, `HTTP ${response.status}`);
    }
    return (await response.json()) as Session;
  } finally {
    window.clearTimeout(timer);
  }
}

export interface FetchState<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
  reload: () => void;
}

/** Загружает JSON по адресу; `null` — ничего не загружать. */
export function useFetch<T>(path: string | null): FetchState<T> {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(path !== null);
  const [error, setError] = useState<string | null>(null);
  const [version, setVersion] = useState(0);

  useEffect(() => {
    if (path === null) {
      setLoading(false);
      return;
    }
    const controller = new AbortController();
    setLoading(true);
    setError(null);
    fetch(path, {
      credentials: 'same-origin',
      headers: { 'X-Requested-With': 'BackpeerAdmin' },
      signal: controller.signal,
    })
      .then(async (response) => {
        if (response.status === 401) {
          unauthorizedHandler?.();
          throw new UnauthorizedError();
        }
        const text = await response.text();
        let body: unknown = null;
        if (text) {
          try {
            body = JSON.parse(text) as unknown;
          } catch {
            throw new ApiError(response.status, 'ответ сервера не JSON');
          }
        }
        if (!response.ok) {
          const message =
            body !== null &&
            typeof body === 'object' &&
            'error' in body &&
            typeof (body as { error: unknown }).error === 'string'
              ? (body as { error: string }).error
              : `HTTP ${response.status}`;
          throw new ApiError(response.status, message);
        }
        return body as T;
      })
      .then((body) => {
        if (!controller.signal.aborted) setData(body);
      })
      .catch((cause: unknown) => {
        if (controller.signal.aborted) return;
        if (cause instanceof DOMException && cause.name === 'AbortError') return;
        setError(cause instanceof Error ? cause.message : 'ошибка загрузки');
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [path, version]);

  const reload = useCallback(() => setVersion((v) => v + 1), []);
  return { data, loading, error, reload };
}

export function download(path: string): void {
  window.location.assign(path);
}
