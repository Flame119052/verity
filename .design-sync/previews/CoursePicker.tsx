import { useState } from 'react';
import { CoursePicker } from 'study-command-center-web';

const COURSES = [
  'Boards-Science-Physics',
  'Boards-Science-Chemistry',
  'Boards-Science-Biology',
  'Boards-Mathematics',
  'IOQM',
  'ZCO/ZIO',
  'Homework',
];

export const SingleLevel = () => {
  const [value, setValue] = useState('Boards-Mathematics');
  return <CoursePicker courses={COURSES} value={value} onPick={setValue} />;
};

export const GroupedOpen = () => {
  const [value, setValue] = useState('Boards-Science-Physics');
  return <CoursePicker courses={COURSES} value={value} onPick={setValue} />;
};
