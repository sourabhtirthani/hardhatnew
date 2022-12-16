/** @type import('hardhat/config').HardhatUserConfig */
require('solidity-coverage')
require( "@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-truffle5");
require('@openzeppelin/hardhat-upgrades');
require("@nomicfoundation/hardhat-chai-matchers");
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
    }
  },
  solidity: {
  compilers: [
    {version: "0.8.16"},
    {version: "0.8.0"},
    {version: "0.8.2"}
  ]
},
paths: {
  sources: "./contracts",
  tests: "./test",
  cache: "./cache",
  artifacts: "./artifacts"
}
};
