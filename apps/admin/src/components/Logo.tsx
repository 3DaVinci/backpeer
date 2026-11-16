export function LogoMark({ className = 'logo-mark' }: { className?: string }) {
  const cells = [];
  for (let row = 0; row < 4; row++) {
    for (let col = 0; col < 5; col++) {
      const on = (row + col) % 2 === 0;
      cells.push(
        <rect
          key={`${row}-${col}`}
          x={col * 4}
          y={row * 4}
          width={3}
          height={3}
          rx={0.6}
          className={on ? 'logo-cell logo-cell-on' : 'logo-cell'}
        />,
      );
    }
  }
  return (
    <svg
      className={className}
      viewBox="0 0 19 15"
      aria-hidden="true"
      focusable="false"
    >
      {cells}
    </svg>
  );
}
