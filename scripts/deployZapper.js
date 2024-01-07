// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {
  const masterchef = '0x0937F4F81f407E1bfACA1FDaA3fDE724d1e727c3';
  const wrappedAsset = '0xd00ae08403B9bbb9124bB305C09058E32C39A48c';
  const router = '0xd7f655E3376cE2D7A2b08fF01Eb3B1023191A901';

  const zapper = await hre.ethers.deployContract("Zapper", 
                                                    [masterchef, 
                                                    wrappedAsset, 
                                                    router
                                                    ]);

  await zapper.waitForDeployment();

  console.log(
    `Contract deployed to ${zapper.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});