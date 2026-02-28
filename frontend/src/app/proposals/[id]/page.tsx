"use client";

import { use } from "react";
import Link from "next/link";
import { formatEther } from "viem";
import { useProposalDetail } from "@/hooks/useProposalDetail";
import { StatusBadge } from "@/components/proposals/StatusBadge";
import { VoteBar } from "@/components/proposals/VoteBar";
import { VoteButtons } from "@/components/proposals/VoteButtons";
import { AIPanel } from "@/components/proposals/AIPanel";
import { ExecuteButton } from "@/components/proposals/ExecuteButton";

export default function ProposalDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const proposalId = parseInt(id, 10);
  const { proposal, userVote, hasRec, aiRec, isExecuted, refetch } = useProposalDetail(proposalId);

  if (!proposal) {
    return (
      <div className="card text-center py-16">
        <p className="text-[var(--text-muted)]">Loading proposal…</p>
      </div>
    );
  }

  const isPastDeadline = Number(proposal.deadline) < Math.floor(Date.now() / 1000);
  const deadline = new Date(Number(proposal.deadline) * 1000).toLocaleString();

  return (
    <div className="flex flex-col gap-6 max-w-2xl">
      <div className="flex items-center gap-3">
        <Link href="/proposals" className="text-[var(--text-muted)] hover:text-white text-sm">
          ← Proposals
        </Link>
        <span className="text-[var(--border)]">/</span>
        <span className="text-sm">#{proposal.id.toString()}</span>
      </div>

      <div className="card flex flex-col gap-4">
        <div className="flex items-start justify-between gap-3">
          <h1 className="text-xl font-bold leading-snug">{proposal.title}</h1>
          <StatusBadge status={proposal.status} />
        </div>

        <p className="text-sm text-[var(--text-muted)] leading-relaxed">{proposal.description}</p>

        <div className="grid grid-cols-2 gap-4 text-sm">
          <div>
            <p className="text-[var(--text-muted)] text-xs mb-1">Requested Funds</p>
            <p className="font-semibold">{formatEther(proposal.fundAmount)} ETH</p>
          </div>
          <div>
            <p className="text-[var(--text-muted)] text-xs mb-1">Destination</p>
            <p className="font-mono text-xs truncate">{proposal.destination}</p>
          </div>
          <div>
            <p className="text-[var(--text-muted)] text-xs mb-1">Proposer</p>
            <p className="font-mono text-xs truncate">{proposal.proposer}</p>
          </div>
          <div>
            <p className="text-[var(--text-muted)] text-xs mb-1">Deadline</p>
            <p>{deadline}</p>
          </div>
        </div>

        <VoteBar votesFor={proposal.votesFor} votesAgainst={proposal.votesAgainst} />
      </div>

      <AIPanel rec={aiRec} />

      <div className="card flex flex-col gap-4">
        <h2 className="font-semibold">Vote</h2>
        <VoteButtons
          proposalId={proposal.id}
          options={proposal.options}
          userVote={userVote}
          status={proposal.status}
          deadline={proposal.deadline}
          onSuccess={refetch}
        />
      </div>

      {(proposal.status === 0 && isPastDeadline) || proposal.status === 1 ? (
        <div className="card flex flex-col gap-3">
          <h2 className="font-semibold">Actions</h2>
          <ExecuteButton
            proposalId={proposal.id}
            status={proposal.status}
            isExecuted={isExecuted}
            onSuccess={refetch}
          />
        </div>
      ) : null}
    </div>
  );
}
