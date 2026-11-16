import { formatNumber } from '../lib/format';

export function BarChart({
  data,
  height = 140,
  format = formatNumber,
  color = 'accent',
}: {
  data: { label: string; value: number }[];
  height?: number;
  format?: (value: number) => string;
  color?: 'accent' | 'warn' | 'bad';
}) {
  const max = Math.max(1, ...data.map((d) => d.value));
  return (
    <div className={`bar-chart bar-chart-${color}`} style={{ height }}>
      {data.map((point) => {
        const heightPercent = (point.value / max) * 100;
        return (
          <div className="bar-column" key={point.label} title={`${point.label}: ${format(point.value)}`}>
            <span className="bar-value">{point.value > 0 ? format(point.value) : ''}</span>
            <span className="bar-track">
              <span
                className="bar-fill"
                style={{ height: `${heightPercent}%` }}
              />
            </span>
            <span className="bar-label">{point.label}</span>
          </div>
        );
      })}
    </div>
  );
}

export function LineChart({
  series,
  height = 180,
  format = formatNumber,
}: {
  series: { name: string; color: string; points: { day: string; count: number }[] }[];
  height?: number;
  format?: (value: number) => string;
}) {
  const width = 720;
  const padding = { top: 14, right: 12, bottom: 28, left: 36 };
  const innerWidth = width - padding.left - padding.right;
  const innerHeight = height - padding.top - padding.bottom;
  const days = series[0]?.points.map((p) => p.day) ?? [];
  const max = Math.max(1, ...series.flatMap((s) => s.points.map((p) => p.count)));
  const x = (index: number) =>
    padding.left +
    (days.length <= 1 ? innerWidth / 2 : (index / (days.length - 1)) * innerWidth);
  const y = (value: number) =>
    padding.top + innerHeight - (value / max) * innerHeight;
  const ticks = [0, Math.ceil(max / 2), max];
  return (
    <div className="line-chart">
      <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label="График">
        {ticks.map((tick) => (
          <g key={tick}>
            <line
              x1={padding.left}
              x2={width - padding.right}
              y1={y(tick)}
              y2={y(tick)}
              className="chart-grid"
            />
            <text x={padding.left - 6} y={y(tick) + 4} textAnchor="end" className="chart-tick">
              {format(tick)}
            </text>
          </g>
        ))}
        {series.map((line) => {
          const path = line.points
            .map((point, index) => `${index === 0 ? 'M' : 'L'}${x(index)},${y(point.count)}`)
            .join(' ');
          return (
            <g key={line.name}>
              <path d={path} fill="none" stroke={line.color} strokeWidth={2.5} />
              {line.points.map((point, index) => (
                <circle
                  key={point.day}
                  cx={x(index)}
                  cy={y(point.count)}
                  r={2.5}
                  fill={line.color}
                >
                  <title>{`${line.name}, ${point.day}: ${format(point.count)}`}</title>
                </circle>
              ))}
            </g>
          );
        })}
        {days.map((day, index) =>
          index % Math.max(1, Math.ceil(days.length / 7)) === 0 ? (
            <text
              key={day}
              x={x(index)}
              y={height - 8}
              textAnchor="middle"
              className="chart-tick"
            >
              {day.slice(5)}
            </text>
          ) : null,
        )}
      </svg>
      <div className="legend">
        {series.map((line) => (
          <span key={line.name}>
            <i style={{ background: line.color }} /> {line.name}
          </span>
        ))}
      </div>
    </div>
  );
}

export function StackedBar({
  parts,
  format = formatNumber,
}: {
  parts: { label: string; value: number; color: string }[];
  format?: (value: number) => string;
}) {
  const total = parts.reduce((sum, part) => sum + part.value, 0);
  return (
    <div className="stacked">
      <div className="stacked-bar">
        {parts.map((part) => (
          <span
            key={part.label}
            style={{
              width: total === 0 ? 0 : `${(part.value / total) * 100}%`,
              background: part.color,
            }}
            title={`${part.label}: ${format(part.value)}`}
          />
        ))}
      </div>
      <div className="legend">
        {parts.map((part) => (
          <span key={part.label}>
            <i style={{ background: part.color }} /> {part.label}{' '}
            <strong>{format(part.value)}</strong>
          </span>
        ))}
      </div>
    </div>
  );
}
