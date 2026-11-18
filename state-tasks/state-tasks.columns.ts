import type { ColDef } from 'ag-grid-community';
import { type Task, taskElapsedMs } from '../../../../core/models/task.model';
import { dateColumn, numberColumn, textColumn } from '../../../../core/utils/grid';
import { EMPTY } from '../../../../core/utils/text';
import { fmtDuration } from '../../../../core/utils/time';
import { CopyRenderer, copyable } from '../../renderers/copy.renderer';
import { stateColumn } from '../../renderers/state.renderer';

export const STATE_TASKS_COLUMNS: ColDef<Task>[] = [
  { field: 'taskId', headerName: 'Task ID', cellClass: 'cell-mono-dim', cellRenderer: CopyRenderer },
  { ...textColumn<Task>('taskName', 'Name', 'cell-plain'), valueFormatter: (p) => p.value || p.data?.methodName || EMPTY },
  copyable(textColumn<Task>('sessionId', 'Session', 'cell-mono-dim')),
  { ...textColumn<Task>('dagName', 'DAG', 'cell-client'), valueFormatter: (p) => p.value || p.data?.dagId || EMPTY },
  stateColumn<Task>('state'),
  copyable(textColumn<Task>('assignedNode', 'Node', 'cell-mono-dim')),
  numberColumn<Task>('requiredCpus', 'CPUs'),
  { ...dateColumn<Task>('submitTimeMs', 'Submitted'), cellClass: 'cell-mono-dim' },
  { ...dateColumn<Task>('completeTimeMs', 'Finished'), cellClass: 'cell-mono-dim' },
  {
    ...numberColumn<Task>('elapsedMs', 'Elapsed'),
    cellClass: 'cell-mono-dim',
    valueGetter: (p) => (p.data ? (p.data.elapsedMs ?? taskElapsedMs(p.data, Date.now())) : -1),
    valueFormatter: (p) => fmtDuration(p.value),
  },
];
