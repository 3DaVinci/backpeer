import { useEffect, useState, type AnchorHTMLAttributes, type ReactNode } from 'react';

/** История браузера без сторонних библиотек: панель — один документ. */
export function navigate(to: string): void {
  if (window.location.pathname + window.location.search === to) return;
  window.history.pushState({}, '', to);
  window.dispatchEvent(new PopStateEvent('popstate'));
}

export function usePath(): string {
  const [path, setPath] = useState(window.location.pathname);
  useEffect(() => {
    const update = () => setPath(window.location.pathname);
    window.addEventListener('popstate', update);
    return () => window.removeEventListener('popstate', update);
  }, []);
  return path;
}

interface LinkProps extends AnchorHTMLAttributes<HTMLAnchorElement> {
  to: string;
  children: ReactNode;
}

export function Link({ to, children, onClick, ...rest }: LinkProps) {
  return (
    <a
      href={to}
      onClick={(event) => {
        onClick?.(event);
        if (
          event.defaultPrevented ||
          event.button !== 0 ||
          event.metaKey ||
          event.ctrlKey ||
          event.shiftKey ||
          event.altKey
        ) {
          return;
        }
        event.preventDefault();
        navigate(to);
      }}
      {...rest}
    >
      {children}
    </a>
  );
}

export function useTitle(title: string | null): void {
  useEffect(() => {
    document.title =
      title === null ? 'Backpeer — панель оператора' : `${title} — Backpeer`;
  }, [title]);
}
