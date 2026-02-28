"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useAccount, useReadContract } from "wagmi";
import { CONTRACTS, OWNER_ADDRESS, DEMO_MODE } from "@/config/contracts";
import { MembershipNFTABI } from "@/abis/MembershipNFT";
import { MOCK_MEMBERSHIP } from "@/lib/mockData";

const NAV = [
  { href: "/", label: "Dashboard" },
  { href: "/proposals", label: "Proposals" },
  { href: "/admin", label: "Admin" },
];

export function Header() {
  const pathname = usePathname();
  const { address, isConnected } = useAccount();

  const { data: isMemberOnChain } = useReadContract({
    address: CONTRACTS.membershipNFT,
    abi: MembershipNFTABI,
    functionName: "checkMembership",
    args: [address!],
    query: { enabled: isConnected && !DEMO_MODE },
  });

  const isMember = DEMO_MODE ? MOCK_MEMBERSHIP.isMember : !!isMemberOnChain;
  const isOwner = isConnected && address?.toLowerCase() === OWNER_ADDRESS;

  return (
    <header className="border-b border-[var(--border)] bg-[var(--surface-2)]">
      <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between gap-6">
        <div className="flex items-center gap-8">
          <Link href="/" className="font-bold text-lg tracking-tight text-white">
            ⬡ VaultMates
          </Link>
          <nav className="flex items-center gap-1">
            {NAV.map(({ href, label }) => (
              <Link
                key={href}
                href={href}
                className={`px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
                  pathname === href
                    ? "bg-[var(--surface-3)] text-white"
                    : "text-[var(--text-muted)] hover:text-white"
                }`}
              >
                {label}
              </Link>
            ))}
          </nav>
        </div>

        <div className="flex items-center gap-3">
          {DEMO_MODE && (
            <span className="text-xs text-[var(--yellow)] border border-[var(--yellow)] border-opacity-30 px-2 py-1 rounded-md">
              Demo Mode
            </span>
          )}
          {isConnected && (
            <div className="flex items-center gap-2">
              {isOwner && <span className="badge badge-owner">👑 Owner</span>}
              {isMember && <span className="badge badge-member">✓ Member</span>}
              {!isMember && !DEMO_MODE && (
                <span className="badge badge-rejected">✗ Not a Member</span>
              )}
            </div>
          )}
          <ConnectButton
            chainStatus="none"
            showBalance={false}
            accountStatus="avatar"
          />
        </div>
      </div>
    </header>
  );
}
