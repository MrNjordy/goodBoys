require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.20",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200
    }
  },
  etherscan: {
    apiKey: {
      metis_goerli: "metis_goerli", // apiKey is not required, just set a placeholder
      snowtrace: "snowtrace", // apiKey is not required, just set a placeholder
    },
    customChains: [
      {
        network: "metisGoerli",
        chainId: 599,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/testnet/evm/599/etherscan",
          browserURL: "https://goerli-explorer.metis.io"
        }
      },
      {
        network: "snowtrace",
        chainId: 43113,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/testnet/evm/43113/etherscan",
          browserURL: "https://avalanche.testnet.routescan.io"
        }
      }
    ]
  },
  networks: {
    mantle: {
      url: "https://rpc.mantle.xyz", //mainnet
      accounts: [process.env.PRIVATE_KEY],
    },
    mantleTest: {
      url: "https://rpc.testnet.mantle.xyz", // testnet
      accounts: [process.env.PRIVATE_KEY]
    },
    metisGoerli: {
      url: "https://goerli.gateway.metisdevops.link	",
      accounts: [process.env.PRIVATE_KEY],
    },
    AvaxTest: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      accounts: [process.env.PRIVATE_KEY],
    }
},
};
