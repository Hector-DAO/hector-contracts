import {
  VotingFarm
} from './../types';
import { Contract } from 'ethers';

const hre = require('hardhat');

export const deployContract = async <ContractType extends Contract>(
  contractName: string,
  args: any[],
  libraries?: {}
) => {
  const signers = await hre.ethers.getSigners();
  const contract = (await (
    await hre.ethers.getContractFactory(contractName, signers[0], {
      libraries: {
        ...libraries,
      },
    })
  ).deploy(...args)) as ContractType;

  return contract;
};

export const deployVotingFarm = async (
  _hec: any,
) => {
  return await deployContract<VotingFarm>('VotingFarm', [
    _hec,
  ]);
};