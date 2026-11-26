import { Component, computed, input, output, signal } from '@angular/core';
import { type NodeView, isGpuNode } from '../../../../core/models/node.model';
import { fmtDate } from '../../../../core/utils/time';
import { CopyTextComponent } from '../../../../shared/copy-text/copy-text.component';

type StateFilter = 'all' | 'online' | 'offline';

interface NodeGroup {
  gpu: boolean;
  label: string;
  icon: string;
  nodes: NodeView[];
}

@Component({
  selector: 'app-tab-nodes',
  imports: [CopyTextComponent],
  templateUrl: './tab-nodes.component.html',
  styleUrl: './tab-nodes.component.scss',
})
export class TabNodesComponent {
  readonly nodes = input.required<NodeView[]>();
  readonly nodeClicked = output<NodeView>();

  protected readonly fmtDate = fmtDate;
  protected readonly query = signal('');
  protected readonly state = signal<StateFilter>('all');
  protected readonly offlineCount = computed(() => this.nodes().filter((n) => !n.online).length);
  protected readonly stateFilters = computed(() => [
    { id: 'all' as const, label: 'All', count: this.nodes().length },
    { id: 'online' as const, label: 'Online', count: this.nodes().length - this.offlineCount() },
    { id: 'offline' as const, label: 'Offline', count: this.offlineCount() },
  ]);
  protected readonly filtered = computed(() => {
    const state = this.state();
    const terms = this.query().trim().toLowerCase().split(/\s+/).filter(Boolean);
    return this.nodes().filter(
      (n) =>
        (state === 'all' || (state === 'online') === n.online) &&
        terms.every((term) => searchText(n).includes(term)),
    );
  });
  private readonly cpuNodes = computed(() => this.nodes().filter((n) => !isGpuNode(n)));
  private readonly gpuNodes = computed(() => this.nodes().filter((n) => isGpuNode(n)));
  protected readonly usedCpus = computed(() => this.cpuNodes().reduce((acc, n) => acc + (n.online ? n.usedCpus : 0), 0));
  protected readonly totalCpus = computed(() => this.cpuNodes().reduce((acc, n) => acc + (n.online ? n.totalCpus : 0), 0));
  protected readonly usedGpus = computed(() => this.gpuNodes().reduce((acc, n) => acc + (n.online ? n.usedGpus : 0), 0));
  protected readonly totalGpus = computed(() => this.gpuNodes().reduce((acc, n) => acc + (n.online ? n.totalGpus : 0), 0));
  protected readonly groups = computed<NodeGroup[]>(() =>
    [
      { gpu: false, label: 'CPU nodes', icon: 'fa-microchip', nodes: this.filtered().filter((n) => !isGpuNode(n)) },
      { gpu: true, label: 'GPU nodes', icon: 'fa-bolt', nodes: this.filtered().filter((n) => isGpuNode(n)) },
    ].filter((g) => g.nodes.length),
  );

  protected slots(node: NodeView): boolean[] {
    return Array.from({ length: node.totalCpus }, (_, i) => i < node.usedCpus);
  }

  protected gpuSlots(node: NodeView): boolean[] {
    return Array.from({ length: node.totalGpus }, (_, i) => i < node.usedGpus);
  }
}

function searchText(node: NodeView): string {
  return [node.hostname, node.nodeId, node.online ? 'online' : 'offline stale dead', isGpuNode(node) ? 'gpu' : 'cpu']
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
}
