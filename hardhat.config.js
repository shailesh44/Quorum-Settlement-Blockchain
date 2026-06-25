require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "istanbul"
    },
  },
  networks: {
    quorum_validator1: {
      url: "http://localhost:8545",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: ["0xaf943b9cb2a1a0f0598143aa712af960e0bdfba39cfbc23ff4b50dbc7a684acc"],
    },
    quorum_validator2: {
      url: "http://localhost:8547",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: ["0xaf943b9cb2a1a0f0598143aa712af960e0bdfba39cfbc23ff4b50dbc7a684acc"],
    },
    quorum_validator3: {
      url: "http://localhost:8549",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: ["0xaf943b9cb2a1a0f0598143aa712af960e0bdfba39cfbc23ff4b50dbc7a684acc"],
    },
    quorum_rpc1: {
      url: "http://localhost:8551",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: ["0xaf943b9cb2a1a0f0598143aa712af960e0bdfba39cfbc23ff4b50dbc7a684acc"],
    },
    quorum_rpc2: {
      url: "http://localhost:8553",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: ["0xaf943b9cb2a1a0f0598143aa712af960e0bdfba39cfbc23ff4b50dbc7a684acc"],
    },
    quorum_local: {
      url: "http://localhost:8545",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: ["0xaf943b9cb2a1a0f0598143aa712af960e0bdfba39cfbc23ff4b50dbc7a684acc"],
    },
  },
};
