import { Component, inject, input, output, signal } from '@angular/core';
import { errorMessage } from '../../../../../core/api/errors';
import { SessionApi } from '../../../../../core/api/session-api.service';
import type { Session } from '../../../../../core/models/session.model';
import { EMPTY } from '../../../../../core/utils/text';

@Component({
  selector: 'app-cancel-session-modal',
  templateUrl: './cancel-session-modal.component.html',
  styleUrl: './cancel-session-modal.component.scss',
  host: { '(document:keydown.escape)': 'close()' },
})
export class CancelSessionModalComponent {
  readonly session = input.required<Session>();
  readonly closed = output<void>();
  readonly cancelled = output<void>();

  private readonly api = inject(SessionApi);

  protected readonly EMPTY = EMPTY;
  protected readonly cancelling = signal(false);
  protected readonly error = signal<string | null>(null);

  protected close(): void {
    if (!this.cancelling()) this.closed.emit();
  }

  protected onOverlayClick(event: MouseEvent): void {
    if (event.target === event.currentTarget) this.close();
  }

  protected async confirm(): Promise<void> {
    if (this.cancelling()) return;
    this.cancelling.set(true);
    this.error.set(null);
    try {
      await this.api.cancel(this.session().sessionId);
      this.cancelled.emit();
    } catch (err) {
      this.error.set(errorMessage(err));
    } finally {
      this.cancelling.set(false);
    }
  }
}
