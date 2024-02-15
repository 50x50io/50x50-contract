import { ethers } from "hardhat";

async function main() {
	const totalSupply = 50;

	const contract = await ethers.deployContract("Sketch", [totalSupply]);

	await contract.waitForDeployment();

	console.log(`${contract.getAddress} contract deployed to ${contract.target}`);
}

main().catch((error) => {
	console.error(error);
	process.exitCode = 1;
});
