import type { SVGProps } from 'react';

const paths: Record<string, string[]> = {
  dashboard: [
    'M3 3h7v7H3z',
    'M14 3h7v4h-7z',
    'M14 11h7v10h-7z',
    'M3 14h7v7H3z',
  ],
  users: [
    'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2',
    'M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8',
    'M22 21v-2a4 4 0 0 0-3-3.87',
    'M16 3.13a4 4 0 0 1 0 7.75',
  ],
  nodes: [
    'M12 2 3 7v10l9 5 9-5V7z',
    'M3 7l9 5 9-5',
    'M12 12v10',
  ],
  network: [
    'M5 12.55a11 11 0 0 1 14 0',
    'M8.5 16.1a6 6 0 0 1 7 0',
    'M2 8.8a16 16 0 0 1 20 0',
    'M12 20h.01',
  ],
  economy: [
    'M12 2v20',
    'M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6',
  ],
  bug: [
    'M8 2l1.5 3',
    'M16 2l-1.5 3',
    'M9 9h6v7a3 3 0 0 1-6 0z',
    'M3 13h3',
    'M18 13h3',
    'M4 9l2 1',
    'M20 9l-2 1',
    'M5 18l2-1',
    'M19 18l-2-1',
  ],
  journal: [
    'M4 4h16v16H4z',
    'M8 8h8',
    'M8 12h8',
    'M8 16h5',
  ],
  system: [
    'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6',
    'M19.4 15a1.7 1.7 0 0 0 .34 1.87l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06A1.7 1.7 0 0 0 15 19.4a1.7 1.7 0 0 0-1 1.55V21a2 2 0 1 1-4 0v-.09A1.7 1.7 0 0 0 9 19.4a1.7 1.7 0 0 0-1.87.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-1.55-1H3a2 2 0 1 1 0-4h.09A1.7 1.7 0 0 0 4.6 9a1.7 1.7 0 0 0-.34-1.87l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.55V3a2 2 0 1 1 4 0v.09A1.7 1.7 0 0 0 15 4.6a1.7 1.7 0 0 0 1.87-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.7 1.7 0 0 0 19.4 9c.14.6.62 1.06 1.22 1.17H21a2 2 0 1 1 0 4h-.09a1.7 1.7 0 0 0-1.51 1',
  ],
  refresh: ['M21 12a9 9 0 1 1-2.64-6.36', 'M21 3v6h-6'],
  logout: ['M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4', 'M16 17l5-5-5-5', 'M21 12H9'],
  search: ['M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16', 'M21 21l-4.35-4.35'],
  copy: [
    'M9 9h11v11H9z',
    'M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1',
  ],
  download: ['M12 3v12', 'M7 10l5 5 5-5', 'M5 21h14'],
  chevron: ['M9 18l6-6-6-6'],
  back: ['M15 18l-6-6 6-6'],
  alert: ['M12 9v4', 'M12 17h.01', 'M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0'],
  check: ['M20 6 9 17l-5-5'],
  eye: ['M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12', 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6'],
  clock: ['M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20', 'M12 6v6l4 2'],
  map: ['M9 18l-6 3V6l6-3 6 3 6-3v15l-6 3z', 'M9 3v15', 'M15 6v15'],
};

interface IconProps extends SVGProps<SVGSVGElement> {
  name: keyof typeof paths;
  size?: number;
}

export function Icon({ name, size = 18, ...rest }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      {...rest}
    >
      {(paths[name] ?? []).map((d, i) => (
        <path key={i} d={d} />
      ))}
    </svg>
  );
}
