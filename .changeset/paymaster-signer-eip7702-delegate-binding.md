---
'openzeppelin-solidity': minor
---

`PaymasterSigner`: Bind the signable digest to the effective EIP-7702 delegate. For senders whose `initCode` is the 20-byte `0x7702` marker, the `initCode` component of the digest is now the delegate read from `userOp.sender`'s code (followed by the trailing initialization data), mirroring the `IEntryPoint`'s `userOpHash` computation. Sponsorship signatures for non-EIP-7702 senders are unchanged.

This changes the digest that sponsorship signers must produce. Signing services that sponsor EIP-7702 senders must be updated in lockstep with the paymaster: they need to sign the substituted `initCode` (the delegate read from the sender's code) rather than the raw marker, otherwise previously working sponsorship will be rejected. See the paymasters guide for the exact value to sign.
