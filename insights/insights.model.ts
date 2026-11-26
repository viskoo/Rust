import type { StreamStatus } from '../../../../core/models/live.model';
import type { MonitorSnapshot } from '../../../../core/models/monitor.model';
import { type NodeView, isGpuNode, toNodeViews } from '../../../../core/models/node.model';

export type HealthLevel = 'ok' | 'warn' | 'down' | 'wait';
export type Tone = 'ready' | 'run' | 'wait' | 'done' | 'fail' | 'off';

export interface Health {
  level: HealthLevel;
  title: string;
  detail: string;
}

export interface Meter {
  used: number;
  total: number;
  pct: number;
  nodes: number;
}

export interface Counter {
  state: string;
  label: string;
  value: number;
  tone: Tone;
}

export interface Insights {
  ready: boolean;
  health: Health;
  cpu: Meter;
  gpu: Meter;
  nodes: { online: number; total: number };
  sessions: { open: number };
  live: Counter[];
}

const SATURATED_PCT = 90;

export function buildInsights(snap: MonitorSnapshot): Insights {
  const overview = snap.overview;
  const nodes = toNodeViews(snap.nodes).sort((a, b) => label(a).localeCompare(label(b), undefined, { numeric: true }));
  const online = nodes.filter((n) => n.online);
  const cpu = meter(nodes.filter((n) => !isGpuNode(n)), (n) => n.totalCpus, (n) => n.availableCpus);
  const gpu = meter(nodes, (n) => n.totalGpus, (n) => n.availableGpus);
  const open = overview?.openSessionTasks ?? {};

  return {
    ready: snap.status === 'live' && overview !== null,
    health: health(snap.status, online.length, cpu.pct),
    cpu,
    gpu,
    nodes: { online: online.length, total: nodes.length },
    sessions: { open: overview?.openSessions ?? 0 },
    live: [
      { state: 'READY', label: 'Queued', value: count(open, 'READY'), tone: 'ready' },
      { state: 'DISPATCHED', label: 'Dispatched', value: count(open, 'DISPATCHED'), tone: 'run' },
      { state: 'COMPLETED', label: 'Completed', value: count(open, 'COMPLETED'), tone: 'done' },
      { state: 'PENDING', label: 'Pending', value: count(open, 'PENDING'), tone: 'wait' },
      { state: 'FAILED', label: 'Failed', value: count(open, 'FAILED'), tone: 'fail' },
      { state: 'CANCELLED', label: 'Canceled', value: count(open, 'CANCELLED'), tone: 'off' },
    ],
  };
}

function health(status: StreamStatus, online: number, cpuPct: number): Health {
  if (status === 'connecting') return { level: 'wait', title: 'Connecting', detail: 'Waiting for live data' };
  if (status !== 'live') return { level: 'down', title: 'Disconnected', detail: 'No live data from the API' };
  if (online === 0) return { level: 'down', title: 'No node online', detail: 'Every node missed its heartbeat' };
  if (cpuPct >= SATURATED_PCT) return { level: 'warn', title: 'Saturated', detail: `${cpuPct}% of the cores busy` };
  return { level: 'ok', title: 'Healthy', detail: `${online} node${online > 1 ? 's' : ''} online` };
}

function meter(nodes: readonly NodeView[], total: (n: NodeView) => number, available: (n: NodeView) => number): Meter {
  const equipped = nodes.filter((n) => total(n) > 0);
  const online = equipped.filter((n) => n.online);
  const all = sum(online, total);
  const used = sum(online, (n) => Math.max(0, total(n) - available(n)));
  const pct = all ? Math.round((used / all) * 100) : 0;
  return { used, total: all, pct, nodes: online.length };
}

function count(counts: Record<string, number>, ...states: string[]): number {
  return states.reduce((acc, state) => acc + (counts[state] ?? 0), 0);
}

function label(node: NodeView): string {
  return node.hostname ?? node.nodeId;
}

function sum<T>(items: readonly T[], value: (item: T) => number): number {
  return items.reduce((acc, item) => acc + (value(item) || 0), 0);
}

export function ageLabel(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  if (s < 2) return 'just now';
  if (s < 60) return `${s} s ago`;
  const m = Math.floor(s / 60);
  return m < 60 ? `${m} min ago` : `${Math.floor(m / 60)} h ago`;
}
