require('dotenv').config();
/**
 * Verifying script in all networks
 * If you want to verify in single network, please use this: yarn test ftm
 */
import exec from 'child_process';

async function main() {
	const cmd = exec.exec;

  	console.log('Verifying on the FTM network...');
	const cmdForVerify = `hardhat verify --contract \"contracts/HecBridgeSplitter.sol:HecBridgeSplitter\" 0x896aa776270fa7Ea74faE540FB9F39E6D5020b76 --network ftm`;
	console.log(cmdForVerify);
	cmd(cmdForVerify, (error) => {
		if (error !== null) {
			console.log(`exec error: ${error}`);
		}
		console.log('Done verify on the FTM network.');
	});
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
