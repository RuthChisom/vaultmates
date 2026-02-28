import Anthropic from "@anthropic-ai/sdk";
import { NextRequest, NextResponse } from "next/server";

const client = new Anthropic();

export async function POST(req: NextRequest) {
  const { title, description, fundAmount, destination } = await req.json();

  if (!title || !description) {
    return NextResponse.json({ error: "title and description are required" }, { status: 400 });
  }

  if (!process.env.ANTHROPIC_API_KEY) {
    return NextResponse.json(
      {
        riskScore: 35,
        rewardScore: 65,
        recommendation:
          "⚠️ ANTHROPIC_API_KEY not set — this is a mock recommendation. " +
          "Add your API key to .env.local to get real Claude AI analysis.",
      },
      { status: 200 }
    );
  }

  const prompt = `You are a DeFi investment advisor for a collaborative DAO treasury called VaultMates.
Analyse the following investment proposal and return a JSON object with exactly three fields:
- riskScore: integer 0–100 (0 = no risk, 100 = extremely high risk)
- rewardScore: integer 0–100 (0 = no reward potential, 100 = exceptional returns)
- recommendation: 2–4 sentence analysis covering risk factors, potential returns, and your recommendation

Proposal Title: ${title}
Description: ${description}
Requested Amount: ${fundAmount} ETH
Destination Address: ${destination}

Respond ONLY with valid JSON. No markdown, no explanation outside the JSON.`;

  const message = await client.messages.create({
    model: "claude-opus-4-6",
    max_tokens: 512,
    messages: [{ role: "user", content: prompt }],
  });

  const raw = (message.content[0] as { text: string }).text.trim();

  let parsed: { riskScore: number; rewardScore: number; recommendation: string };
  try {
    parsed = JSON.parse(raw);
  } catch {
    return NextResponse.json({ error: "Failed to parse Claude response", raw }, { status: 500 });
  }

  return NextResponse.json(parsed);
}
