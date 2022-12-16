require("@nomiclabs/hardhat-waffle");
const { deployProxy, upgradeProxy } = require('@openzeppelin/truffle-upgrades');
const hre = require("hardhat");
const { expect } = require('chai');
var chai = require('chai');
const BN = require('bn.js');
const { ethers ,upgrades } = require('hardhat');
chai.use(require('chai-bn')(BN));
const EXOToken = artifacts.require('EXOToken');
const GCREDToken = artifacts.require('GCREDToken');
const Governance = artifacts.require('Governance');
const StakingReward = artifacts.require('StakingReward');
const Bridge = artifacts.require('Bridge');


describe('my first test',async (accounts)=>{
  // const [minter, alice, bob, BRIDGE_CONTRACT, STAKING_CONTRACT, MD_ADDRESS, DAO_ADDRESS] = accounts;
  let EXO_token,EXO,GCREDToken,GCRED
  before(async()=>{
    EXO_token = await hre.ethers.getContractFactory('EXOToken');
    EXO = await upgrades.deployProxy(EXO_token,[])
    EXO_token = await EXO_token.deploy();
    GCREDToken = await hre.ethers.getContractFactory('GCREDToken');
    GCRED = await upgrades.deployProxy(GCREDToken,["0xC8934823c0a96e9b0170098D975902d22E22f84c","0xC8934823c0a96e9b0170098D975902d22E22f84c"])
  })

  it('Test correct setting of vanity information',async()=>{
    const name = await EXO.name();
    expect(name).to.equal('EXO Token');
     
    const symbol = await EXO.symbol();
    expect(symbol).to.equal('EXO');
  })

  it('Revert: only bridge contract can mint', async () => {
     
     const BRIDGE_ROLE = await EXO.BRIDGE_ROLE();
     const [owner, otherAccount] = await ethers.getSigners();
      await expect( EXO.connect(otherAccount).bridgeMint(otherAccount.address, 0, { from: otherAccount.address })).to.be.revertedWith(`AccessControl: account ${otherAccount.address} is missing role ${BRIDGE_ROLE}`);
  })

  it('Bridge mint', async () => {
    const [owner, otherAccount] = await ethers.getSigners();
    const BRIDGE_ROLE = await EXO.BRIDGE_ROLE();
    const BRIDGE_CONTRACT=otherAccount.address
    await EXO.connect(otherAccount).grantRole(BRIDGE_ROLE, BRIDGE_CONTRACT);
    console.log("BRIDGE_CONTRACT",BRIDGE_CONTRACT);
    await EXO.connect(otherAccount).bridgeMint("0xC8934823c0a96e9b0170098D975902d22E22f84c", BigInt(100*(10**18)), { from: BRIDGE_CONTRACT });
    const balanceOfBob = await EXO.balanceOf(bob);
    expect(balanceOfBob.toString()).to.equal(BigInt(100*(10**18)));
  })

  it('Bridge mint', async () => {
    const [owner, otherAccount] = await ethers.getSigners();
    const BRIDGE_ROLE = await EXO.BRIDGE_ROLE();
    const BRIDGE_CONTRACT=otherAccount.address
    await EXO.connect(otherAccount).grantRole(BRIDGE_ROLE, BRIDGE_CONTRACT);
    await EXO.connect(otherAccount).bridgeBurn("0xC8934823c0a96e9b0170098D975902d22E22f84c", BigInt(100*(10**18)), { from: BRIDGE_CONTRACT });
    const balanceOfBob = await EXO.balanceOf(bob);
    expect(balanceOfBob.toString()).to.equal(BigInt(100*(10**18)));
  })
})