import { Component } from '@angular/core';
import { ENVIRONMENT } from '../../core/environment';

@Component({
  selector: 'app-env-badge',
  template: '{{ env }}',
  styleUrl: './env-badge.component.scss',
  host: { '[class]': "'env-' + env.toLowerCase()", '[title]': "'Environment: ' + env" },
})
export class EnvBadgeComponent {
  protected readonly env = ENVIRONMENT;
}
