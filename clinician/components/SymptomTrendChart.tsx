"use client";

const GRADE_COLORS: Record<number, string> = {
  0: "#16A974",
  1: "#E8A33D",
  2: "#F2683C",
  3: "#E5484D",
};

const GRADE_LABELS: Record<number, string> = {
  0: "None",
  1: "Mild",
  2: "Moderate",
  3: "Severe",
};

interface DailyGrade {
  date: string;
  maxGrade: number;
  count: number;
}

export function SymptomTrendChart({
  reports,
}: {
  reports: { reported_at: string; grade: number }[];
}) {
  if (reports.length === 0) {
    return (
      <p style={{ padding: 24, textAlign: "center", color: "var(--hint)", fontSize: 15 }}>
        No symptom data to chart.
      </p>
    );
  }

  const byDate = new Map<string, number[]>();
  for (const r of reports) {
    const day = r.reported_at.slice(0, 10);
    const list = byDate.get(day) ?? [];
    list.push(r.grade);
    byDate.set(day, list);
  }

  const days: DailyGrade[] = [];
  for (const [date, grades] of byDate) {
    days.push({
      date,
      maxGrade: Math.max(...grades),
      count: grades.length,
    });
  }
  days.sort((a, b) => a.date.localeCompare(b.date));

  const WIDTH = 600;
  const HEIGHT = 180;
  const PAD = { top: 16, right: 16, bottom: 32, left: 40 };
  const chartW = WIDTH - PAD.left - PAD.right;
  const chartH = HEIGHT - PAD.top - PAD.bottom;
  const barGap = 4;
  const barW = Math.max(12, Math.min(40, (chartW - barGap * (days.length - 1)) / days.length));
  const totalW = days.length * barW + (days.length - 1) * barGap;
  const offsetX = Math.max(0, (chartW - totalW) / 2);

  return (
    <div style={{ overflowX: "auto", padding: "8px 0" }}>
      <svg width={WIDTH} height={HEIGHT} viewBox={`0 0 ${WIDTH} ${HEIGHT}`}>
        {/* Grid lines + grade labels */}
        {[0, 1, 2, 3].map((g) => {
          const y = PAD.top + chartH - (g / 3) * chartH;
          return (
            <g key={g}>
              <line
                x1={PAD.left}
                y1={y}
                x2={WIDTH - PAD.right}
                y2={y}
                stroke="var(--hairline)"
                strokeWidth={1}
              />
              <text
                x={PAD.left - 8}
                y={y + 4}
                textAnchor="end"
                fill="var(--hint)"
                fontSize={11}
              >
                {GRADE_LABELS[g]}
              </text>
            </g>
          );
        })}

        {/* Bars */}
        {days.map((d, i) => {
          const x = PAD.left + offsetX + i * (barW + barGap);
          const h = (d.maxGrade / 3) * chartH;
          const y = PAD.top + chartH - h;
          const color = GRADE_COLORS[d.maxGrade] ?? "var(--hint)";

          return (
            <g key={d.date}>
              <rect
                x={x}
                y={y}
                width={barW}
                height={Math.max(h, 2)}
                rx={4}
                fill={color}
                opacity={0.85}
              />
              <text
                x={x + barW / 2}
                y={PAD.top + chartH + 16}
                textAnchor="middle"
                fill="var(--hint)"
                fontSize={10}
              >
                {d.date.slice(5)}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}
