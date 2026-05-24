import { ethers } from 'ethers';

export const address = {
  random: () => ethers.Wallet.createRandom().address,
  zero: ethers.ZeroAddress,
};
export const bytes32 = {
  random: () => ethers.hexlify(ethers.randomBytes(32)),
  zero: ethers.ZeroHash,
};
export const bytes4 = {
  random: () => ethers.hexlify(ethers.randomBytes(4)),
  zero: ethers.zeroPadBytes('0x', 4),
};
export const uint256 = {
  random: () => ethers.toBigInt(ethers.randomBytes(32)),
  zero: 0n,
};
export const int256 = {
  random: () => ethers.toBigInt(ethers.randomBytes(32)) + ethers.MinInt256,
  zero: 0n,
};
export const bytes = {
  random: (length = 32) => ethers.randomBytes(length),
  zero: new Uint8Array(),
};
export const hex = {
  random: (length = 32) => ethers.hexlify(ethers.randomBytes(length)),
  zero: '0x',
};
export const string = {
  random: () => ethers.uuidV4(ethers.randomBytes(32)),
  zero: '',
};
