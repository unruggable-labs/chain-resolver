import { Foundry }      from '@adraffy/blocksmith';
import axios            from 'axios';
import { SENDER_ADDR }  from './addresses.js';

let foundry = null;
let impersonatedSigner = null;

export const init = async () => {

    if (!foundry || !impersonatedSigner) {

        const PROVIDER_URL = process.env.MAINNET_RPC_URL;

        foundry = await Foundry.launch({
            infoLog: false,
            fork: PROVIDER_URL,
        });

        await foundry.provider.send('anvil_impersonateAccount', [
            SENDER_ADDR
        ]);

        // Get a signer for the impersonated address
        impersonatedSigner = await foundry.provider.getSigner(SENDER_ADDR);
    }

    return { foundry, impersonatedSigner };
}

// See documentation https://docs.tenderly.co/simulations/bundled-simulations
// transactions "get simulated one after another within the same block."
export const simulateTransactionBundle = async (transactions) => {

    console.log("Simulating transactions with Tenderly...");

    const API_KEY = process.env.TENDERLY_API_KEY;
    const USERNAME = process.env.TENDERLY_USERNAME;
    const PROJECT = process.env.TENDERLY_PROJECT;

  
    const url = `https://api.tenderly.co/api/v1/account/${USERNAME}/project/${PROJECT}/simulate-bundle`;

    console.log("URL:", url);
    //process.exit(0);
  
    const payload = {
      network_id: "1",
      block_number: "latest",
      simulations: transactions,
    };
  
    try {
      const response = await axios.post(url, payload, {
        headers: {
          "X-Access-Key": API_KEY,
          "Content-Type": "application/json"
        }
      });
  
      // console.log("Simulation Results:", response.data);
      console.log("Simulation successful");

      for (let sim of response.data["simulation_results"]) {

        const simulationId = sim["simulation"]["id"];
        const shareUrl = `https://api.tenderly.co/api/v1/account/${USERNAME}/project/${PROJECT}/simulations/${simulationId}/share`;

        const options = {
          method: 'POST',
          url: shareUrl,
          headers: {
            "X-Access-Key": API_KEY,
            "Content-Type": "application/json"
          }
        };

        try {
          
          const { status, data } = await axios.request(options);

          if (status == 204) {
            console.log(`https://www.tdly.co/shared/simulation/${simulationId}`);
          } else {
            console.error("Failed to share simulation", simulationId);
          }

        } catch (error) {
          
          console.error(error);
        }
      }

      /*
      // response.data["simulation_results"]["0"]["simulation"]
      [
        "id", "project_id", "owner_id", "network_id", "block_number", "transaction_index", "from", "to",
        "input", "gas", "gas_price", "gas_used", "value", "method", "status", "access_list", "queue_origin",
        "block_header", "deposit_tx", "system_tx", "nonce", "addresses", "contract_ids", "shared", "created_at"
      ]
      */

    } catch (error) {

      console.error("Error during simulation:", error.response?.data || error.message);
    }
};


export const assert = (condition, message) => {
    if (!condition) {
            throw new Error(message || "Assertion failed");
    }
}