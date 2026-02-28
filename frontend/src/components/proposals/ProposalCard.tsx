"use client";

import Link from "next/link";
import { formatEther } from "viem";
import { StatusBadge } from "./StatusBadge";
import { VoteBar } from "./VoteBar";

interface Proposal {
  id: bigint;
  title: string;
  description: string;
  fundAmount: bigint;
  votesFor: bigint;
  votesAgainst: bigint;
  deadline: bigint;
  status: number;
}

function countdown(deadline: bigint) {
  const diff = Number(deadline) - Math.floor(Date.now() / 1000);
  if (diff <= 0) return "Ended";
  const d = Math.floor(diff / 86400);
  const h = Math.floor((diff % 86400) / 3600);
  return d > 0 ? `${d}d ${h}h left` : `${h}h left`;
}

export function ProposalCard({ proposal }: { proposal: Proposal }) {
  return (
    <Link href={`/proposals/${proposal.id}`}>
      <div className="card hover:border-[var(--brand)] transition-colors cursor-pointer flex flex-col gap-3">
        <div className="flex items-start justify-between gap-2">
          <div>
            <div className="text-xs text-[var(--text-muted)] mb-1">#{proposal.id.toString()}</div>
            <h3 className="font-semibold leading-snug">{proposal.title}</h3>
          </div>
          <StatusBadge status={proposal.status} />
        </div>

        <p className="text-sm text-[var(--text-muted)] line-clamp-2">{proposal.description}</p>

        <VoteBar votesFor={proposal.votesFor} votesAgainst={proposal.votesAgainst} />

        <div className="flex justify-between text-xs text-[var(--text-muted)]">
          <span>{formatEther(proposal.fundAmount)} ETH requested</span>
          <span>{countdown(proposal.deadline)}</span>
        </div>
      </div>
    </Link>
  );
}
