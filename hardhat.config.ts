import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";
dotenv.config();

const INFURA_API_KEY = process.env.INFURA_API_KEY!;
const PRIVATE_KEY = process.env.SECRET_KEY!;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY!;

const config: HardhatUserConfig = {
	solidity: "0.8.20",
	etherscan: {
		apiKey: {
			"blast-sepolia": "blast-sepolia", // apiKey is not required, just set a placeholder
		},
		customChains: [
			{
				network: "blast-sepolia",
				chainId: 168587773,
				urls: {
					apiURL: "https://api.routescan.io/v2/network/testnet/evm/168587773/etherscan",
					browserURL: "https://testnet.blastscan.io",
				},
			},
		],
	},
	networks: {
		"blast-sepolia": {
			url: "https://rpc.ankr.com/blast_testnet_sepolia/02b15d3cf3ef0cd419e47dd779a47704b0455a733cd142834c12febf4df208ab",
			accounts: [PRIVATE_KEY],
		},
	},
};

export default config;
