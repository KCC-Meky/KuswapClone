// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');
  var singAddress = await hre.ethers.getSigners()
  singAddress = singAddress[0]['address']
  //Deploy Wrapped Native token
  const WKCS = await hre.ethers.getContractFactory("WKCS");
  const wkcs = await WKCS.deploy(singAddress, 53, singAddress)
  await wkcs.deployed()
  console.log("wkcs deployed to:", wkcs.address);


  //Deploy factory
  const Factory = await hre.ethers.getContractFactory('KuswapFactory');
  const factory = await Factory.deploy(singAddress)
  await factory.deployed()
  console.log("KUS factory :", factory.address)
  console.log("INIT HASH :",await factory.INIT_CODE_HASH())

  // change hash in Router then comment all previous and run 
  // const wKcsAddres = ''
  // const factoryAddress = ''
  // const Router = await hre.ethers.getContractFactory('KuswapRouter02');
  // const router = await Router.deploy(factoryAddress, wKcsAddres)
  // await router.deployed()
  // console.log("KUS Router :", router.address)  
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
