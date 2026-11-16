export interface Session {
  user: string;
  expiresAt: string;
}

export interface ApiErrorBody {
  error?: string;
}

export interface Page<T> {
  items: T[];
  total: number;
  page: number;
  limit: number;
}

export interface SeriesPoint {
  day: string;
  count: number;
}

export interface NameCount {
  name: string;
  count: number;
}

export interface ReportSummary {
  total: number;
  last24h: number;
  last7d: number;
  byDay: { day: string; count: number }[];
  byVersion: NameCount[];
  byOs: NameCount[];
  top: NameCount[];
}

export interface AccountSummary {
  accountId: string;
  login: string | null;
  createdAt: string;
  blockedAt: string | null;
  blockedReason: string | null;
  objectBytes: number;
  fragmentBytes: number;
  balanceMc: number;
  negativeSince: string | null;
  devicesActive: number;
  nodesActive: number;
  nodesOnline: number;
  segmentsActive: number;
  lastActivityAt: string | null;
}

export interface DeviceEntry {
  deviceId: string;
  addedAt: string;
  revokedAt: string | null;
  revokedBy: 'account' | 'operator' | null;
}

export interface ObjectGroup {
  kind: 'snapshots' | 'indexes';
  count: number;
  bytes: number;
  lastAt: string | null;
}

export interface SegmentGroup {
  state: string;
  count: number;
  bytes: number;
  lastAt: string | null;
}

export interface AccountNode {
  nodeId: string;
  country: string | null;
  city: string | null;
  capacityBytes: number;
  usedBytes: number;
  assignedBytes: number;
  availability: number;
  online: boolean;
  lastHeartbeatAt: string | null;
  removedAt: string | null;
  excludedAt: string | null;
  leavingAt: string | null;
  lostAt: string | null;
  software: string;
  registeredAt: string;
  relay: string | null;
  relayUntil: string | null;
}

export interface LedgerEntry {
  amountMc: number;
  kind: string;
  day: string;
  ref: string;
  note: string;
  createdAt: string | null;
}

export interface TrafficEntry {
  day: string;
  method: 'direct' | 'udp' | 'relay' | string;
  bytes: number;
  connections: number;
}

export interface RelayUsageEntry {
  day: string;
  bytes: number;
  sessions: number;
}

export interface Quota {
  dataBytes: number;
  reservedBytes: number;
  capacityBytes: number;
  barterBytes: number;
  maxBytes: number;
  balanceMc: number;
  availableMc: number;
  billableBytes: number;
  monthlyCostMc: number;
  dailyCostMc: number;
  earnedMc: number;
  spentMc: number;
  negativeSince: string | null;
  graceDays: number;
  graceUntil: string | null;
  blocked: boolean;
}

export interface AccountDetail {
  accountId: string;
  login: string | null;
  createdAt: string;
  keyCopy: boolean;
  keyCopyUpdatedAt: string | null;
  objectBytes: number;
  fragmentBytes: number;
  blockedAt: string | null;
  blockedReason: string | null;
  balanceMc: number;
  negativeSince: string | null;
  devices: DeviceEntry[];
  objects: ObjectGroup[];
  segments: SegmentGroup[];
  nodes: AccountNode[];
  ledger: LedgerEntry[];
  traffic: TrafficEntry[];
  relay: RelayUsageEntry[];
  quota: Quota;
}

export interface NodeSummary {
  nodeId: string;
  accountId?: string;
  ownerLogin: string | null;
  country: string | null;
  city: string | null;
  registeredAt: string;
  removedAt?: string | null;
  excludedAt?: string | null;
  excludedReason?: string | null;
  leavingAt?: string | null;
  lostAt?: string | null;
  lastHeartbeatAt: string | null;
  capacityBytes: number;
  usedBytes: number;
  assignedBytes: number;
  freeBytes: number;
  availability: number;
  software: string;
  auditsPassed: number;
  auditsFailed: number;
  auditWindowFailures: number;
  auditLatencyMs: number | null;
  lastAuditAt: string | null;
  relay: string | null;
  relayUntil: string | null;
  onProbation: boolean;
  endpointCount?: number;
  endpoints?: string[];
  online: boolean;
  status: NodeStatus;
  reputation: number;
  reconcileAt?: string | null;
  repairSuspendedUntil?: string | null;
}

export type NodeStatus =
  | 'online'
  | 'offline'
  | 'lost'
  | 'excluded'
  | 'leaving'
  | 'removed';

export interface AuditEntry {
  at: string;
  passed: boolean;
  recheck: boolean;
  reason: string | null;
  latencyMs: number;
  nodeId: string;
  software?: string;
  country?: string | null;
  ownerLogin?: string | null;
}

export interface NodeJob {
  jobId: string;
  kind: 'repair' | 'relocate' | string;
  state: string;
  createdAt: string;
  finishedAt: string | null;
  plannedBytes: number;
  bytesDownloaded: number;
  bytesUploaded: number;
}

export interface NodeDetail extends NodeSummary {
  latitude: number | null;
  longitude: number | null;
  storedFragments: number;
  damagedFragments: number;
  segmentsCount: number;
  storedBytes: number;
  audits: Omit<AuditEntry, 'nodeId'>[];
  jobs: NodeJob[];
  uptime: { day: string; online: number }[];
}

export interface SegmentSummary {
  accountId: string;
  login: string | null;
  segmentId: string;
  k: number;
  n: number;
  repairThreshold: number;
  fragmentSize: number;
  state: 'pending' | 'ok' | 'repair' | 'unknown';
  live: number;
  allocatedAt: string;
  committedAt: string | null;
  repairSince: string | null;
  storedFragments: number;
  damagedFragments: number;
  dataBytes: number;
}

export interface SegmentFragment {
  idx: number;
  nodeId: string;
  ownerLogin: string | null;
  country: string | null;
  city: string | null;
  stored: boolean;
  damagedAt: string | null;
  auditFailedAt: string | null;
  auditedAt: string | null;
  nodeRemovedAt: string | null;
  nodeLastHeartbeatAt: string | null;
  online: boolean;
}

export interface SegmentDetail extends SegmentSummary {
  fragments: SegmentFragment[];
}

export interface NodeStats {
  accounts: number;
  accountsBlocked: number;
  devicesActive: number;
  nodes: number;
  nodesOnline: number;
  nodesExcluded: number;
  nodesOnProbation: number;
  capacityBytes: number;
  objectBytes: number;
  fragmentBytes: number;
  segments: Record<string, number>;
  segmentsByStoredFragments: Record<string, number>;
}

export interface Overview {
  generatedAt: string;
  stats: NodeStats;
  dataBytes: number;
  objectsCount: number;
  storedFragments: number;
  damagedFragments: number;
  nodesFreeBytes: number;
  nodesUsedBytes: number;
  nodesAssignedBytes: number;
  economy: {
    balanceMc: number;
    negativeAccounts: number;
    blockedAccounts: number;
    earnedMc: number;
    spentMc: number;
    graceDays: number;
    starterCredits: number;
  };
  audits: {
    passed24h: number;
    failed24h: number;
    latencyMs: number | null;
    lastAt: string | null;
  };
  repair: { running: number; queue: number; minLive: number | null };
  traffic: Record<
    string,
    { bytes: number; connections: number; accounts: number }
  >;
  versions: NameCount[];
  countries: { code: string; count: number }[];
  activity: { accounts: SeriesPoint[]; nodes: SeriesPoint[] };
  journal: JournalEntry[];
  reports: ReportSummary;
  recentReports?: CrashReport[];
}

export interface RelayStats {
  days: number;
  relays: {
    relay: string;
    lastReportAt: string;
    listeners: number;
    sessions: number;
    sessionsOpened: number;
    bytes: number;
    nodesAssigned: number;
  }[];
  nodesOnRelay: number;
  accountsUsingRelay: number;
  traffic: Record<
    string,
    { bytes: number; connections: number; accounts: number }
  >;
  relayShare: number | null;
}

export interface RepairStats {
  hours: number;
  segments: number;
  storedDataBytes: number;
  queue: { segments: number; byLive: Record<string, number> };
  minLive: number | null;
  nodesLost: number;
  executorsSuspended: number;
  jobs: { running: number; verifying: number; done: number; failed: number };
  fragmentsRestored: number;
  fragmentsFailedAudit: number;
  traffic: {
    plannedBytes: number;
    downloadedBytes: number;
    uploadedBytes: number;
    bytesPerTbPerDay: number | null;
    modelBytesPerTbPerDay: number;
  };
  relocations: {
    nodesLeaving: number;
    running: number;
    done: number;
    failed: number;
    uploadedBytes: number;
  };
}

export interface NetworkAudits {
  passed: number;
  failed: number;
  latencyMs: number | null;
  reasons: { reason: string; count: number }[];
  recent: AuditEntry[];
}

export interface Network {
  hours: number;
  stats: NodeStats;
  relay: RelayStats;
  repair: RepairStats;
  audits: NetworkAudits;
}

export interface RepairJob {
  jobId: string;
  accountId: string;
  login: string | null;
  segmentId: string;
  executorNodeId: string;
  executorLogin: string | null;
  kind: 'repair' | 'relocate';
  state: 'running' | 'verifying' | 'done' | 'failed';
  live: number;
  plannedBytes: number;
  bytesDownloaded: number;
  bytesUploaded: number;
  createdAt: string;
  deadline: string;
  reportedAt: string | null;
  finishedAt: string | null;
  reason: string | null;
  targetsDone: number;
  targetsTotal: number;
}

export interface AuditPage {
  id: number;
  at: string;
  passed: boolean;
  recheck: boolean;
  reason: string | null;
  latencyMs: number;
  nodeId: string;
  software: string;
  country: string | null;
  ownerLogin: string | null;
}

export interface Economy {
  days: number;
  policy: {
    dataCreditsPerTbMonth: number;
    storeCreditsPerTbMonth: number;
    barterRatio: number;
    starterCredits: number;
    graceDays: number;
  };
  summary: {
    accounts: number;
    totalMc: number;
    positiveAccounts: number;
    negativeAccounts: number;
    positiveMc: number;
    negativeMc: number;
    blockedAccounts: number;
  };
  topPositive: { login: string | null; accountId: string; balanceMc: number }[];
  topNegative: {
    login: string | null;
    accountId: string;
    balanceMc: number;
    negativeSince: string | null;
  }[];
  ledger: (LedgerEntry & { login: string | null; accountId: string })[];
  daily: { day: string; earnedMc: number; spentMc: number; entries: number }[];
}

export interface JournalEntry {
  id: number;
  at: string;
  osUser: string;
  dbUser: string;
  command: string;
  arguments: unknown;
  reason: string | null;
  result: string;
}

export interface CrashReport {
  id: string;
  at: string;
  receivedAt: string;
  version: string;
  os: string;
  error: string;
  stack: string;
  source: string;
}

export interface CrashReportPage extends Page<CrashReport> {
  summary: ReportSummary;
}

export interface SystemInfo {
  database: {
    user: string;
    name: string;
    version: string;
    schema: number;
    readOnlyRole: string;
    readOnly: boolean;
  };
  counts: {
    accounts: number;
    devicesActive: number;
    nodesActive: number;
    segments: number;
    fragments: number;
    audits: number;
    repairJobs: number;
    creditAccounts: number;
    creditEntries: number;
  };
  service: {
    version: string;
    startedAt: string;
    uptimeSeconds: number;
    sessions: number;
    operators: number;
    reports: ReportSummary;
  };
  config: {
    host: string;
    port: number;
    publicUrl: string | null;
    staticDir: string;
    reportsDir: string;
    reportRetentionDays: number;
    reportPerHour: number;
    sessionHours: number;
    onlineWindowMinutes: number;
    probationHours: number;
    cookieSecure: boolean;
    trustForwardedFor: boolean;
    readOnlyRole: string;
    economy: {
      dataCreditsPerTbMonth: number;
      storeCreditsPerTbMonth: number;
      barterRatio: number;
      starterCredits: number;
      graceDays: number;
    };
  };
}
