const STATUS_MAP: Record<number, { label: string; cls: string }> = {
  0: { label: "Active",     cls: "badge-active" },
  1: { label: "Passed",    cls: "badge-passed" },
  2: { label: "Rejected",  cls: "badge-rejected" },
  3: { label: "Executed",  cls: "badge-executed" },
  4: { label: "Cancelled", cls: "badge-cancelled" },
};

export function StatusBadge({ status }: { status: number }) {
  const s = STATUS_MAP[status] ?? STATUS_MAP[4];
  return <span className={`badge ${s.cls}`}>{s.label}</span>;
}
