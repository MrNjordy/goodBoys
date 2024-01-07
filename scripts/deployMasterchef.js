// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {
  const initialOwner = '0xFc931A1246024068b3b398bD0B546d36151530D2'
  const nativeToken = '0x802451fD962E963dA9aFC043abe559C9A802781b'
  const initialRewards = '1000000000000000000'
  const initialTimestamp = (await hre.ethers.provider.getBlock('latest')).timestamp;
  const router = '0xd7f655E3376cE2D7A2b08fF01Eb3B1023191A901';
  const wrappedAsset = '0xd00ae08403B9bbb9124bB305C09058E32C39A48c';

  const masterchef = await hre.ethers.deployContract("Masterchef", 
                                                      [initialOwner, 
                                                        nativeToken, 
                                                        initialOwner, 
                                                        initialOwner, 
                                                        initialRewards, 
                                                        initialTimestamp, 
                                                        router, 
                                                        wrappedAsset
                                                      ]);

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
