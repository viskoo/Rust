import { DecimalPipe } from '@angular/common';
import { Component, input, output } from '@angular/core';
import { AgGridAngular } from 'ag-grid-angular';
import type { GridOptions } from 'ag-grid-community';
import { PagedLiveQuery } from '../../../../core/live/paged-live-query';
import type { SessionTarget } from '../../../../core/models/session.model';
import { type Task, taskTarget } from '../../../../core/models/task.model';
import { ColumnPrefs } from '../../../../core/utils/column-prefs';
import { SERVER_PAGED_OPTIONS, onRowOpen, rowToneRules, withCatalog } from '../../../../core/utils/grid';
import { displayState } from '../../../../core/utils/state';
import { ColumnPickerComponent } from '../../../../shared/column-picker/column-picker.component';
import { PagedGridComponent } from '../../../../shared/paged-grid/paged-grid.component';
import { StreamStatusComponent } from '../../../../shared/stream-status/stream-status.component';
import { TASK_CATALOG } from '../../columns/catalog';
import { STATE_TASKS_COLUMNS } from './state-tasks.columns';

@Component({
  selector: 'app-state-tasks',
  imports: [AgGridAngular, ColumnPickerComponent, DecimalPipe, PagedGridComponent, StreamStatusComponent],
  templateUrl: './state-tasks.component.html',
  styleUrl: './state-tasks.component.scss',
})
export class StateTasksComponent {
  readonly state = input.required<string>();
  readonly taskOpened = output<SessionTarget>();

  protected readonly displayState = displayState;
  protected readonly columns = new ColumnPrefs<Task>(() => 'state-tasks', () => withCatalog(STATE_TASKS_COLUMNS, TASK_CATALOG));

  protected readonly tasks = new PagedLiveQuery<Task>({
    table: 'tasks',
    key: (task) => task.taskId,
    defaultSort: () => ({ field: 'submitTimeMs', descending: true }),
    fixedFilters: () => [
      { field: 'state', op: 'equals', value: this.state() },
      { field: 'sessionState', op: 'equals', value: 'OPEN' },
    ],
  });

  protected readonly gridOptions: GridOptions<Task> = {
    ...SERVER_PAGED_OPTIONS,
    suppressNoRowsOverlay: true,
    getRowId: (p) => p.data.taskId,
    rowClassRules: rowToneRules((task) => task.state),
    onGridReady: (e) => this.tasks.showDefaultSort(e.api),
    onSortChanged: this.tasks.onSortChanged,
    onFilterChanged: this.tasks.onFilterChanged,
    onRowClicked: onRowOpen((task) => this.taskOpened.emit(taskTarget(task))),
  };
}
