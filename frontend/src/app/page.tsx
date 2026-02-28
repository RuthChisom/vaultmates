"use client";

import { StatCards } from "@/components/dashboard/StatCards";
import { DepositForm } from "@/components/dashboard/DepositForm";
import { WithdrawForm } from "@/components/dashboard/WithdrawForm";
import { useVaultStats } from "@/hooks/useVaultStats";

export default function DashboardPage() {
  const stats = useVaultStats();

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-2xl font-bold mb-1">Dashboard</h1>
        <p className="text-[var(--text-muted)] text-sm">
          Manage your share of the collaborative vault treasury.
        </p>
      </div>

      <StatCards
        totalAssets={stats.totalAssets}
        userBalance={stats.userBalance}
        memberCount={stats.memberCount}
        proposalCount={stats.proposalCount}
        quorumBps={stats.quorumBps}
      />

      <div className="grid md:grid-cols-2 gap-6">
        <div className="card">
          <h2 className="font-semibold mb-4">Deposit ETH</h2>
          <DepositForm onSuccess={stats.refetch} />
        </div>
        <div className="card">
          <h2 className="font-semibold mb-4">Withdraw ETH</h2>
          <WithdrawForm onSuccess={stats.refetch} />
        </div>
      </div>

      <div className="card">
        <h2 className="font-semibold mb-3">How VaultMates Works</h2>
        <ol className="text-sm text-[var(--text-muted)] flex flex-col gap-2 list-decimal list-inside">
          <li>Members deposit ETH into the shared vault treasury.</li>
          <li>Any member can create an investment proposal.</li>
          <li>Claude AI analyses each proposal — risk score, reward score, recommendation.</li>
          <li>Members review the AI analysis and vote on proposals.</li>
          <li>Approved proposals are executed automatically, moving funds on-chain.</li>
        </ol>
      </div>
    </div>
  );
}
