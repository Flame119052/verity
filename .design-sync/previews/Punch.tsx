import { Punch } from 'study-command-center-web';

export const AllStatuses = () => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
    <Punch status="completed" minutes={45} />
    <Punch status="partial" minutes={20} />
    <Punch status="not_logged" />
    <Punch status="pending" />
    <Punch status="not_tracked" />
  </div>
);
