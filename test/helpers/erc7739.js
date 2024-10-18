const { ethers } = require('hardhat');
const { domainType, formatType } = require('./eip712');

class PersonalSignHelper {
  static types = { PersonalSign: formatType({ prefixed: 'bytes' }) };

  static prepare(message) {
    return {
      prefixed: ethers.concat([
        ethers.toUtf8Bytes(ethers.MessagePrefix),
        ethers.toUtf8Bytes(String(message.length)),
        typeof message === 'string' ? ethers.toUtf8Bytes(message) : message,
      ]),
    };
  }

  static hash(message) {
    return message.prefixed ? ethers.keccak256(message.prefixed) : ethers.hashMessage(message);
  }

  static sign(signer, data, signerDomain) {
    return signer.signTypedData(signerDomain, this.types, data.prefixed ? data : this.prepare(data));
  }
}

class TypedDataSignHelper {
  constructor(contentsTypes, contentsTypeName = Object.keys(contentsTypes).at(0)) {
    this.contentsTypes = contentsTypes;
    this.contentsTypeName = contentsTypeName;
  }

  static from(contentsTypes, contentsTypeName = Object.keys(contentsTypes).at(0)) {
    return new TypedDataSignHelper(contentsTypes, contentsTypeName);
  }

  hash(domain, message) {
    return message.signerDomain
      ? ethers.TypedDataEncoder.hash(domain, this.#allTypes(message), message)
      : ethers.TypedDataEncoder.hash(domain, this.contentsTypes, message);
  }

  sign(signer, domain, message) {
    const types = this.#allTypes(message);
    const typedDataSignType = ethers.TypedDataEncoder.from(types).encodeType('TypedDataSign');
    const signerDomainType = ethers.TypedDataEncoder.from(types).encodeType('EIP712Domain');
    const contentsAndDomainType = typedDataSignType.slice(typedDataSignType.indexOf(')') + 1); // Remove TypedDataSign (first object)
    const domainOffset = contentsAndDomainType.indexOf(signerDomainType);
    const contentsType = contentsAndDomainType.replace(signerDomainType, ''); // Remove EIP712Domain
    const contentsDescr = contentsType + (contentsType.startsWith(this.contentsTypeName) ? '' : this.contentsTypeName);
    const contentsDescrLength = contentsDescr.length;

    return signer
      .signTypedData(domain, types, message)
      .then(signature =>
        ethers.concat([
          signature,
          ethers.TypedDataEncoder.hashDomain(domain),
          ethers.TypedDataEncoder.hashStruct(this.contentsTypeName, types, message.contents),
          ethers.toUtf8Bytes(contentsDescr),
          ethers.toBeHex(domainOffset, 2),
          ethers.toBeHex(contentsDescrLength, 2),
        ]),
      );
  }

  static hash(domain, types, message) {
    return TypedDataSignHelper.from(types).hash(domain, message);
  }

  static sign(signer, domain, types, message) {
    return TypedDataSignHelper.from(types).sign(signer, domain, message);
  }

  // internal
  #allTypes(message) {
    return {
      TypedDataSign: formatType({ contents: this.contentsTypeName, signerDomain: 'EIP712Domain' }),
      EIP712Domain: domainType(message.signerDomain),
      ...this.contentsTypes,
    };
  }
}

module.exports = {
  PersonalSignHelper,
  TypedDataSignHelper,
};
