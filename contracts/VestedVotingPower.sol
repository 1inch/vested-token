// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IStepVesting.sol";
import "./interfaces/ISt1inch.sol";
import "./interfaces/IVestedToken.sol";
import "./VotingPowerCalculator.sol";

contract VestedVotingPower is Ownable, VotingPowerCalculator {
    using EnumerableSet for EnumerableSet.AddressSet;

    IVestedToken public immutable vestedToken;
    mapping (address => EnumerableSet.AddressSet) private _vestingsByReceiver;

    uint256 private constant _VOTING_POWER_DIVIDER = 20;

    constructor(IVestedToken _vestedToken, ISt1inch st1inch) VotingPowerCalculator(st1inch.expBase(), st1inch.origin()) {
        vestedToken = _vestedToken;
    }

    function vestedTokenTransferOwnership(address newOwner) external onlyOwner {
        vestedToken.transferOwnership(newOwner);
    }

    function vestingsByReceiver(address receiver) external view returns (address[] memory) {
        return _vestingsByReceiver[receiver].values();
    }

    function votingPowerOf(address account) external view returns (uint256 votingPower) {
        EnumerableSet.AddressSet storage vestings = _vestingsByReceiver[account];
        uint256 len = vestings.length();
        unchecked {
            for (uint256 i = 0; i < len; i++) {
                IStepVesting vesting = IStepVesting(vestings.at(i));
                uint256 started = vesting.started();
                uint256 cliffDuration = vesting.cliffDuration();
                uint256 stepDuration = vesting.stepDuration();
                uint256 cliffAmount = vesting.cliffAmount();
                uint256 numOfSteps = vesting.numOfSteps();
                uint256 stepAmount = vesting.stepAmount();
                uint256 claimed = vesting.claimed();
                if (claimed < cliffAmount) {
                    votingPower += Math.min(cliffAmount, _votingPowerAt(_balanceAt(cliffAmount / _VOTING_POWER_DIVIDER, started + cliffDuration), block.timestamp));
                }
                for (uint256 j = 0; j < numOfSteps; j++) {
                    if (claimed < cliffAmount + stepAmount * (j + 1)) {
                        votingPower += Math.min(stepAmount, _votingPowerAt(_balanceAt(stepAmount / _VOTING_POWER_DIVIDER, started + cliffDuration + stepDuration * (j + 1)), block.timestamp));
                    }
                }
            }
        }
        return votingPower;
    }

    function registerVestings(address[] calldata vestings) external onlyOwner {
        if (vestedToken.owner() == address(this)) {
            vestedToken.registerVestings(vestings);
        }
        uint256 len = vestings.length;
        unchecked {
            for (uint256 i = 0; i < len; i++) {
                address vesting = vestings[i];
                address receiver = IStepVesting(vesting).receiver();
                require(_vestingsByReceiver[receiver].add(vesting), "Vesting is already registered");
            }
        }
    }

    function deregisterVestings(address[] calldata vestings) external onlyOwner {
        if (vestedToken.owner() == address(this)) {
            vestedToken.deregisterVestings(vestings);
        }
        uint256 len = vestings.length;
        unchecked {
            for (uint256 i = 0; i < len; i++) {
                address vesting = vestings[i];
                address receiver = IStepVesting(vesting).receiver();
                EnumerableSet.AddressSet storage receiverVestings = _vestingsByReceiver[receiver];
                require(receiverVestings.remove(vesting), "Vesting is not registered");
            }
        }
    }
}
