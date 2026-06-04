// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Flags2Env {
    struct Pair {
        string key;
        string value;
    }

    function hash(Pair[] memory pairs) internal pure returns (bytes32) {
        return keccak256(abi.encode(pairs));
    }

    function requireHash(Pair[] memory pairs, bytes32 expectedHash) internal pure {
        require(hash(pairs) == expectedHash, "flags2env: hash mismatch");
    }

    function get(Pair[] memory pairs, string memory key) internal pure returns (bool found, string memory value) {
        bytes32 wanted = keccak256(bytes(key));
        for (uint256 i = 0; i < pairs.length; i++) {
            if (keccak256(bytes(pairs[i].key)) == wanted) {
                return (true, pairs[i].value);
            }
        }
        return (false, "");
    }
}
