// Hand-written entry for the design-sync converter. apps/web has no library
// build, so the auto-synthesized entry (every src/ file re-exported) pulled in
// main.tsx's top-level ReactDOM.createRoot(...).render(...) side effect, which
// throws in any environment without a #root element and crashes window.Verity
// before it's assigned. This entry re-exports only the real components.
export { default as App } from '../apps/web/src/App';
export { TimerProvider } from '../apps/web/src/timer';
export {
  Strip,
  Stamp,
  Punch,
  Fault,
  Loading,
  KeyHint,
  CoursePicker,
} from '../apps/web/src/board';
export { RackView } from '../apps/web/src/views/RackView';
export { ChronoView } from '../apps/web/src/views/ChronoView';
export { PendingView } from '../apps/web/src/views/PendingView';
export { RosterView } from '../apps/web/src/views/RosterView';
export { TallyView } from '../apps/web/src/views/TallyView';
export { DispatchView } from '../apps/web/src/views/DispatchView';
