import { KeyHint } from 'study-command-center-web';

export const Board = () => (
  <div style={{ display: 'flex', gap: 16 }}>
    <KeyHint k="1–6" label="board" />
    <KeyHint k="R" label="rack" />
    <KeyHint k="ESC" label="cancel" />
  </div>
);
