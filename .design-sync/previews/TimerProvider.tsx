import { TimerProvider } from 'study-command-center-web';

export const WithChild = () => (
  <TimerProvider>
    <div style={{ padding: 12, fontFamily: 'var(--mono)' }}>
      timer context ready — children render through unaffected
    </div>
  </TimerProvider>
);
