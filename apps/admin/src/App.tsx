import { useEffect, useState } from 'react';
import { currentSession, logout, setUnauthorizedHandler } from './api';
import { Layout } from './components/Layout';
import { Loading } from './components/ui';
import { Dashboard } from './pages/Dashboard';
import { EconomyPage } from './pages/Economy';
import { Journal } from './pages/Journal';
import { Login } from './pages/Login';
import { NetworkPage } from './pages/Network';
import { NodeDetail } from './pages/NodeDetail';
import { Nodes } from './pages/Nodes';
import { NotFound } from './pages/NotFound';
import { ReportDetail, Reports } from './pages/Reports';
import { SegmentDetailPage } from './pages/SegmentDetail';
import { Segments } from './pages/Segments';
import { System } from './pages/System';
import { UserDetail } from './pages/UserDetail';
import { Users } from './pages/Users';
import { usePath } from './lib/router';
import type { Session } from './types';

export function App() {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  const path = usePath();

  useEffect(() => {
    let alive = true;
    currentSession()
      .then((value) => {
        if (alive) setSession(value);
      })
      .catch(() => {
        if (alive) setSession(null);
      });
    return () => {
      alive = false;
    };
  }, []);

  useEffect(() => {
    setUnauthorizedHandler(() => setSession(null));
    return () => setUnauthorizedHandler(null);
  }, []);

  if (session === undefined) {
    return (
      <div className="boot">
        <Loading label="Проверка сессии…" />
      </div>
    );
  }
  if (session === null) {
    return <Login onSuccess={setSession} />;
  }
  return (
    <Layout
      path={path}
      user={session.user}
      onLogout={() => {
        void logout().catch(() => undefined);
        setSession(null);
      }}
    >
      {route(path)}
    </Layout>
  );
}

function route(path: string) {
  const parts = path.split('/').filter(Boolean).map(decodeURIComponent);
  if (parts.length === 0) return <Dashboard />;
  if (parts[0] === 'users' && parts.length === 1) return <Users />;
  if (parts[0] === 'users' && parts[1]) return <UserDetail accountId={parts[1]} />;
  if (parts[0] === 'nodes' && parts.length === 1) return <Nodes />;
  if (parts[0] === 'nodes' && parts[1]) return <NodeDetail nodeId={parts[1]} />;
  if (parts[0] === 'segments' && parts.length === 1) return <Segments />;
  if (parts[0] === 'segments' && parts[1] && parts[2])
    return <SegmentDetailPage accountId={parts[1]} segmentId={parts[2]} />;
  if (parts[0] === 'network') return <NetworkPage />;
  if (parts[0] === 'economy') return <EconomyPage />;
  if (parts[0] === 'reports' && parts.length === 1) return <Reports />;
  if (parts[0] === 'reports' && parts[1]) return <ReportDetail id={parts[1]} />;
  if (parts[0] === 'journal') return <Journal />;
  if (parts[0] === 'system') return <System />;
  return <NotFound />;
}
