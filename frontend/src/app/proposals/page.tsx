"use client";

import { useState } from "react";
import Link from "next/link";
import { ProposalCard } from "@/components/proposals/ProposalCard";
import { useProposals } from "@/hooks/useProposals";

const STATUS_LABELS: Record<number, string> = {
  0: "Active", 1: "Passed", 2: "Rejected", 3: "Executed", 4: "Cancelled",
};

export default function ProposalsPage() {
  const { proposals, refetch } = useProposals();
  const [filter, setFilter] = useState<number | null>(null);

  const filtered = filter === null ? proposals : proposals.filter((p) => p.status === filter);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold mb-1">Proposals</h1>
          <p className="text-[var(--text-muted)] text-sm">
            Browse, vote, and execute DAO investment proposals.
          </p>
        </div>
        <Link href="/proposals/new" className="btn btn-primary">+ New Proposal</Link>
      </div>

      <div className="flex gap-2 flex-wrap">
        <button
          className={`btn btn-secondary text-xs ${filter === null ? "border-[var(--brand)] text-white" : ""}`}
          onClick={() => setFilter(null)}
        >
          All ({proposals.length})
        </button>
        {[0, 1, 2, 3, 4].map((s) => {
          const count = proposals.filter((p) => p.status === s).length;
          if (count === 0) return null;
          return (
            <button
              key={s}
              className={`btn btn-secondary text-xs ${filter === s ? "border-[var(--brand)] text-white" : ""}`}
              onClick={() => setFilter(s)}
            >
              {STATUS_LABELS[s]} ({count})
            </button>
          );
        })}
      </div>

      {filtered.length === 0 ? (
        <div className="card text-center py-12 text-[var(--text-muted)]">
          <p className="text-3xl mb-3">📭</p>
          <p>No proposals yet. Be the first to create one!</p>
        </div>
      ) : (
        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtered.map((p) => (
            <ProposalCard key={p.id.toString()} proposal={p} />
          ))}
        </div>
      )}
    </div>
  );
}
