import { ethers } from 'ethers';

const toBytes = input => (ethers.isBytesLike(input) ? ethers.getBytes(input) : ethers.toUtf8Bytes(input));
export const sortBytes = (inputs, fn = x => x) =>
  inputs.toSorted((a, b) => Buffer.compare(toBytes(fn(a)), toBytes(fn(b))));
export const sortBytesByHash = (inputs, fn = x => x) => sortBytes(inputs, x => ethers.keccak256(toBytes(fn(x))));

export const address = {
  random: () => ethers.Wallet.createRandom().address,
  sort: sortBytes,
  sortByHash: sortBytesByHash,
  zero: ethers.ZeroAddress,
};
export const bytes32 = {
  random: () => ethers.hexlify(ethers.randomBytes(32)),
  from: input => ethers.hexZeroPad(ethers.getBytes(input), 32),
  sort: sortBytes,
  sortByHash: sortBytesByHash,
  zero: ethers.ZeroHash,
};
export const bytes4 = {
  random: () => ethers.hexlify(ethers.randomBytes(4)),
  from: input => ethers.hexZeroPad(ethers.getBytes(input), 4),
  zero: ethers.zeroPadBytes('0x', 4),
};
export const uint256 = {
  random: () => ethers.toBigInt(ethers.randomBytes(32)),
  from: input => ethers.toBigInt(input),
  sort: inputs => inputs.toSorted((a, b) => (a < b ? -1 : a > b ? 1 : 0)),
  zero: 0n,
};
export const int256 = {
  random: () => ethers.toBigInt(ethers.randomBytes(32)) + ethers.MinInt256,
  from: input => ethers.toBigInt(input),
  sort: inputs => inputs.toSorted((a, b) => (a < b ? -1 : a > b ? 1 : 0)),
  zero: 0n,
};
export const bytes = {
  random: (length = 32) => ethers.randomBytes(length),
  from: input => toBytes(input),
  sort: sortBytes,
  sortByHash: sortBytesByHash,
  zero: new Uint8Array(),
};
export const hexBytes = {
  random: (length = 32) => ethers.hexlify(ethers.randomBytes(length)),
  from: input => ethers.hexlify(toBytes(input)),
  sort: sortBytes,
  sortByHash: sortBytesByHash,
  zero: '0x',
};
export const string = {
  random: () => ethers.uuidV4(ethers.randomBytes(32)),
  from: input => String(input),
  sort: inputs => inputs.toSorted(),
  zero: '',
};
