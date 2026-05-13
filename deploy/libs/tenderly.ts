/**
 * Tenderly bundle simulation helper.
 *
 * Ports proposal/utils/utils.js#simulateTransactionBundle into TypeScript and
 * parameterises the network id so we can simulate on sepolia as well as
 * mainnet. Used by DoUpgrade.ts to dry-run upgradeToAndCall before signing
 * the real transaction.
 *
 * See: https://docs.tenderly.co/simulations/bundled-simulations
 */

import axios from "axios";

export interface TenderlyTxInput {
  from: string;
  to: string;
  input: string;
  value?: string;
}

export interface TenderlyResult {
  simulationId: string;
  status: boolean;
  shareUrl: string | null;
  gasUsed?: number;
  errorMessage?: string;
}

const REQUIRED_ENV = ["TENDERLY_API_KEY", "TENDERLY_USERNAME", "TENDERLY_PROJECT"] as const;

function readEnv() {
  const missing = REQUIRED_ENV.filter((k) => !process.env[k]);
  if (missing.length > 0) {
    throw new Error(
      `Tenderly env vars missing: ${missing.join(", ")}. Set them in .env or skip simulation.`
    );
  }
  return {
    apiKey: process.env.TENDERLY_API_KEY!,
    username: process.env.TENDERLY_USERNAME!,
    project: process.env.TENDERLY_PROJECT!,
  };
}

/**
 * Simulate a bundle of transactions on Tenderly against the latest block of
 * the given network. Each transaction runs sequentially within a single
 * simulated block. Returns one result per transaction (including a shareable
 * link if the simulation was saved + shared successfully).
 */
export async function simulateTransactionBundle(
  transactions: TenderlyTxInput[],
  chainId: number
): Promise<TenderlyResult[]> {
  const { apiKey, username, project } = readEnv();

  const url = `https://api.tenderly.co/api/v1/account/${username}/project/${project}/simulate-bundle`;

  const networkId = String(chainId);
  const defaults = {
    network_id: networkId,
    save: true,
    save_if_fails: true,
    simulation_type: "full",
  };

  const simulations = transactions.map((t) => ({ ...defaults, ...t }));
  const payload = {
    network_id: networkId,
    block_number: "latest",
    simulations,
  };

  const response = await axios.post(url, payload, {
    headers: {
      "X-Access-Key": apiKey,
      "Content-Type": "application/json",
    },
  });

  const results: TenderlyResult[] = [];
  for (const sim of response.data.simulation_results ?? []) {
    const simulationId = sim?.simulation?.id;
    const status = Boolean(sim?.transaction?.status);
    const gasUsed = sim?.transaction?.gas_used;
    const errorMessage = sim?.transaction?.error_message;

    let shareUrl: string | null = null;
    if (simulationId) {
      try {
        const shareEndpoint = `https://api.tenderly.co/api/v1/account/${username}/project/${project}/simulations/${simulationId}/share`;
        const shareRes = await axios.post(shareEndpoint, undefined, {
          headers: {
            "X-Access-Key": apiKey,
            "Content-Type": "application/json",
          },
        });
        if (shareRes.status === 204) {
          shareUrl = `https://www.tdly.co/shared/simulation/${simulationId}`;
        }
      } catch {
        // sharing is best-effort; the simulation itself is still recorded
      }
    }

    results.push({ simulationId, status, shareUrl, gasUsed, errorMessage });
  }

  return results;
}

/**
 * Helper for the common single-transaction case.
 */
export async function simulateTransaction(
  tx: TenderlyTxInput,
  chainId: number
): Promise<TenderlyResult> {
  const [result] = await simulateTransactionBundle([tx], chainId);
  if (!result) {
    throw new Error("Tenderly returned no simulation result");
  }
  return result;
}
