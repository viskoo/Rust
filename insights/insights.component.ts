import { DecimalPipe, NgTemplateOutlet } from '@angular/common';
import { Component, computed, effect, input, output, signal, untracked } from '@angular/core';
import type { MonitorSnapshot } from '../../../../core/models/monitor.model';
import { injectNow } from '../../../../core/utils/clock';
import { GaugeComponent } from '../../../../shared/gauge/gauge.component';
import { ServiceHealthComponent } from '../../../../shared/service-health/service-health.component';
import { ageLabel, buildInsights } from './insights.model';

@Component({
  selector: 'app-insights',
  imports: [DecimalPipe, GaugeComponent, NgTemplateOutlet, ServiceHealthComponent],
  templateUrl: './insights.component.html',
  styleUrl: './insights.component.scss',
})
export class InsightsComponent {
  readonly snap = input.required<MonitorSnapshot>();
  readonly stateSelected = output<string>();

  private readonly now = injectNow();
  private readonly updatedAt = signal(Date.now());

  protected readonly insights = computed(() => buildInsights(this.snap()));
  protected readonly freshness = computed(() => ageLabel(this.now() - this.updatedAt()));

  constructor() {
    effect(() => {
      this.snap();
      untracked(() => this.updatedAt.set(Date.now()));
    });
  }
}
