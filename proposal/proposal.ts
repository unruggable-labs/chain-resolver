import { Contract, keccak256, toUtf8Bytes, Interface, namehash } from 'ethers';
import { BASE_REGISTRAR_ABI, ENS_REGISTRY_ABI } from './utils/abis.js';
import { BASE_REGISTRAR_ADDRESS, DAO_WALLET_ADDRESS, SENDER_ADDR, ENS_REGISTRY_ADDRESS, RESOLVER_ADDRESS } from './utils/addresses.js';
import { init, assert, simulateTransactionBundle } from './utils/utils.js';

// Check RESOLVER_ADDRESS is defined
if (!RESOLVER_ADDRESS) {
  console.error("❌ RESOLVER_ADDRESS is not defined in proposal/utils/addresses.js");
  console.error("   Set it to your deployed ChainResolver proxy address before running.");
  process.exit(1);
}

const { foundry, impersonatedSigner } = await init();

// Check RESOLVER_ADDRESS is a contract
const resolverCode = await foundry.provider.getCode(RESOLVER_ADDRESS);
if (!resolverCode || resolverCode === "0x") {
  console.error("❌ RESOLVER_ADDRESS is not a contract:", RESOLVER_ADDRESS);
  console.error("   Make sure you've deployed the ChainResolver proxy first.");
  await foundry.shutdown();
  process.exit(1);
}

console.log("✓ Resolver is a contract:", RESOLVER_ADDRESS);

// Create contract instances for encoding calldata
const baseRegistrarInterface = new Interface(BASE_REGISTRAR_ABI);
const ensRegistryInterface = new Interface(ENS_REGISTRY_ABI);

const baseRegistrar = new Contract(
  BASE_REGISTRAR_ADDRESS,
  BASE_REGISTRAR_ABI,
  foundry.provider
);

const ensRegistry = new Contract(
  ENS_REGISTRY_ADDRESS,
  ENS_REGISTRY_ABI,
  foundry.provider
);

console.log("\n=== ENS 'on.eth' Registration Proposal ===\n");

// Step 1: Check current state
const registrarOwner = await baseRegistrar.owner!();
console.log("BaseRegistrar owner:", registrarOwner);
console.log("DAO Wallet:", DAO_WALLET_ADDRESS);
console.log("Sender (impersonated):", SENDER_ADDR);

// Check if DAO wallet is already a controller
const isController = await baseRegistrar.controllers!(DAO_WALLET_ADDRESS);
console.log("\nDAO Wallet is controller:", isController);

// Proposal transactions array (for output)
const proposalTransactions: { to: string; value: string; calldata: string; description: string }[] = [];

// Track state for conditional logic
let addedController = false;
let registrationSucceeded = false;

// Step 2: Add DAO wallet as controller if not already
if (!isController) {
  console.log("\n--- Transaction 1: Add DAO Wallet as Controller ---");
  
  const addControllerArgs = [DAO_WALLET_ADDRESS];
  const addControllerCalldata = baseRegistrarInterface.encodeFunctionData("addController", addControllerArgs);
  
  console.log("Target:", BASE_REGISTRAR_ADDRESS);
  console.log("Arguments:", addControllerArgs);
  console.log("Calldata:", addControllerCalldata);
  
  proposalTransactions.push({
    to: BASE_REGISTRAR_ADDRESS,
    value: "0",
    calldata: addControllerCalldata,
    description: "Add DAO Wallet as BaseRegistrar controller"
  });
  
  // Execute via sendTransaction
  const addControllerTx = await impersonatedSigner.sendTransaction({
    to: BASE_REGISTRAR_ADDRESS,
    data: addControllerCalldata,
  });
  await addControllerTx.wait();
  console.log("✓ Transaction executed");

  // Verify
  const isNowController = await baseRegistrar.controllers!(DAO_WALLET_ADDRESS);
  assert(isNowController, "Failed to add controller");
  console.log("✓ Verified: DAO Wallet is now a controller");
  addedController = true;
} else {
  console.log("✓ DAO Wallet is already a controller (skipping addController)");
}

// Step 3: Register 'on.eth'
console.log("\n--- Transaction 2: Register 'on.eth' ---");

const label = "on";
const labelhash = keccak256(toUtf8Bytes(label));
const tokenId = BigInt(labelhash);

console.log("Label:", label);
console.log("Labelhash:", labelhash);
console.log("Token ID:", tokenId.toString());

// Check if name is available
const isAvailable = await baseRegistrar.available!(tokenId);
console.log("Name available:", isAvailable);

if (!isAvailable) {
  // Check who owns it
  try {
    const currentOwner = await baseRegistrar.ownerOf!(tokenId);
    const expires = await baseRegistrar.nameExpires!(tokenId);
    console.log("Current owner:", currentOwner);
    console.log("Expires:", new Date(Number(expires) * 1000).toISOString());
  } catch (e) {
    console.log("Name exists but may be expired");
  }
}

if (isAvailable) {
  // Register for 10 years (in seconds)
  const duration = 10n * 365n * 24n * 60n * 60n; // 10 years
  
  const registerArgs = [tokenId, DAO_WALLET_ADDRESS, duration];
  const registerCalldata = baseRegistrarInterface.encodeFunctionData("register", registerArgs);
  
  console.log("\nTarget:", BASE_REGISTRAR_ADDRESS);
  console.log("Arguments:", registerArgs);
  console.log("Calldata:", registerCalldata);
  
  proposalTransactions.push({
    to: BASE_REGISTRAR_ADDRESS,
    value: "0",
    calldata: registerCalldata,
    description: `Register 'on.eth' for ${duration / (365n * 24n * 60n * 60n)} years to DAO Wallet`
  });
  
  // Execute via sendTransaction
  const registerTx = await impersonatedSigner.sendTransaction({
    to: BASE_REGISTRAR_ADDRESS,
    data: registerCalldata,
  });
  await registerTx.wait();
  console.log("✓ Transaction executed");

  // Verify ownership
  const newOwner = await baseRegistrar.ownerOf!(tokenId);
  console.log("New owner:", newOwner);
  assert(
    newOwner.toLowerCase() === DAO_WALLET_ADDRESS.toLowerCase(),
    "Owner mismatch after registration"
  );
  console.log("✓ Verified: DAO Wallet owns 'on.eth'");
  registrationSucceeded = true;

  const newExpires = await baseRegistrar.nameExpires!(tokenId);
  console.log("Expires:", new Date(Number(newExpires) * 1000).toISOString());
} else {
  console.log("\n⚠️  Name is not available for registration");
}

// Step 4: Set resolver for 'on.eth' (only if registration succeeded)
if (registrationSucceeded) {
  console.log("\n--- Transaction 3: Set Resolver for 'on.eth' ---");

  const onEthNamehash = namehash("on.eth");
  console.log("Namehash (on.eth):", onEthNamehash);

  const setResolverArgs = [onEthNamehash, RESOLVER_ADDRESS];
  const setResolverCalldata = ensRegistryInterface.encodeFunctionData("setResolver", setResolverArgs);

  console.log("Target:", ENS_REGISTRY_ADDRESS);
  console.log("Arguments:", setResolverArgs);
  console.log("Calldata:", setResolverCalldata);

  proposalTransactions.push({
    to: ENS_REGISTRY_ADDRESS,
    value: "0",
    calldata: setResolverCalldata,
    description: `Set resolver for 'on.eth' to ${RESOLVER_ADDRESS}`
  });

  // Execute via sendTransaction
  const setResolverTx = await impersonatedSigner.sendTransaction({
    to: ENS_REGISTRY_ADDRESS,
    data: setResolverCalldata,
  });
  await setResolverTx.wait();
  console.log("✓ Transaction executed");

  // Verify resolver was set
  const currentResolver = await ensRegistry.resolver!(onEthNamehash);
  console.log("Current resolver:", currentResolver);
  assert(
    currentResolver.toLowerCase() === RESOLVER_ADDRESS.toLowerCase(),
    "Resolver mismatch after setting"
  );
  console.log("✓ Verified: Resolver set correctly");
} else {
  console.log("\n⚠️  Skipping setResolver (registration did not succeed)");
}

// Step 5: Remove DAO wallet as controller (cleanup - only if we added it)
if (addedController) {
  console.log("\n--- Transaction 4: Remove DAO Wallet as Controller ---");

  const removeControllerArgs = [DAO_WALLET_ADDRESS];
  const removeControllerCalldata = baseRegistrarInterface.encodeFunctionData("removeController", removeControllerArgs);

  console.log("Target:", BASE_REGISTRAR_ADDRESS);
  console.log("Arguments:", removeControllerArgs);
  console.log("Calldata:", removeControllerCalldata);

  proposalTransactions.push({
    to: BASE_REGISTRAR_ADDRESS,
    value: "0",
    calldata: removeControllerCalldata,
    description: "Remove DAO Wallet as BaseRegistrar controller"
  });

  // Execute via sendTransaction
  const removeControllerTx = await impersonatedSigner.sendTransaction({
    to: BASE_REGISTRAR_ADDRESS,
    data: removeControllerCalldata,
  });
  await removeControllerTx.wait();
  console.log("✓ Transaction executed");

  // Verify
  const isStillController = await baseRegistrar.controllers!(DAO_WALLET_ADDRESS);
  assert(!isStillController, "Failed to remove controller");
  console.log("✓ Verified: DAO Wallet is no longer a controller");
} else {
  console.log("\n✓ Skipping removeController (was already a controller before proposal)");
}

// Output proposal summary
console.log("\n========================================");
console.log("=== PROPOSAL CALLDATA SUMMARY ===");
console.log("========================================\n");

if (proposalTransactions.length === 0) {
  console.log("⚠️  No transactions generated. Registration may have failed.");
  await foundry.shutdown();
  process.exit(1);
}

for (let i = 0; i < proposalTransactions.length; i++) {
  const tx = proposalTransactions[i]!;
  console.log(`--- Transaction ${i + 1}: ${tx.description} ---`);
  console.log("To:", tx.to);
  console.log("Value:", tx.value);
  console.log("Calldata:", tx.calldata);
  console.log("");
}

// Output as JSON for easy copy-paste
console.log("--- JSON Format (for proposal submission) ---");
console.log(JSON.stringify(proposalTransactions, (_, v) => 
  typeof v === 'bigint' ? v.toString() : v, 2));

// Simulate with Tenderly
console.log("\n========================================");
console.log("=== TENDERLY SIMULATION ===");
console.log("========================================\n");

// Format transactions for Tenderly API
const transactions = proposalTransactions.map((tx) => ({
  from: SENDER_ADDR,
  to: tx.to,
  input: tx.calldata,
}));

const defaults = {
  network_id: '1',
  save: true,
  save_if_fails: true,
  simulation_type: 'full',
};

const tenderlyTransactions = transactions.map((item) => ({ ...defaults, ...item }));

console.log("Tenderly transactions:", JSON.stringify(tenderlyTransactions, null, 2));

await simulateTransactionBundle(tenderlyTransactions);

console.log("\n=== Proposal Simulation Complete ===");

// Cleanup
await foundry.shutdown();
