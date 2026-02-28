"use client";

import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { anvil, flowTestnet } from "wagmi/chains";

export const wagmiConfig = getDefaultConfig({
  appName: "VaultMates",
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "demo",
  chains: [anvil, flowTestnet],
  ssr: true,
});
