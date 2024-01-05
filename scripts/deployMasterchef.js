// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {
  const initialOwner = '0xFc931A1246024068b3b398bD0B546d36151530D2'
  const nativeToken = '0x63CB893bA22e3017A23C41d8388dFFdF984cd8bc'
  const initialRewards = '2000000000000000000'
  const initialBock = 1

  const masterchef = await hre.ethers.deployContract("Masterchef", [initialOwner, nativeToken, initialOwner, initialOwner, initialRewards, initialBock]);

  await masterchef.waitForDeployment();

  console.log(
    `Contract deployed to ${masterchef.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
