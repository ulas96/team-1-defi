// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/* @title Stabletoken
* @author Ulas Yildiz
* @notice ERC20 stablecoin token (symbol: SBT) whose supply is controlled exclusively by the owner.
* @dev Intended to be owned by the StabletokenEngine contract, which calls mint/burn in response
*      to collateral operations. Extends OpenZeppelin ERC20Burnable and Ownable.
*/
contract Stabletoken is ERC20Burnable, Ownable {
    error Stabletoken__ZeroAmount();
    error Stabletoken__ExceedsBalance();
    error Stabletoken__ZeroAddress();

    /// @notice Deploys the token and sets the deployer as the initial owner.
    constructor() ERC20("Stabletoken", "SBT") Ownable(msg.sender) {}

    /// @notice Burns `_amount` tokens from the owner's balance.
    /// @dev Overrides ERC20Burnable.burn to restrict access to the owner.
    /// @param _amount The number of tokens to burn.
    function burn(uint256 _amount) public override onlyOwner {
        require(_amount >= 0, Stabletoken__ZeroAmount());
        require(balanceOf(msg.sender) >= _amount, Stabletoken__ExceedsBalance());
        super.burn(_amount);
    }

    /// @notice Mints `_amount` tokens to address `_to`.
    /// @dev Only callable by the owner (expected to be StabletokenEngine).
    /// @param _to The address to receive the minted tokens.
    /// @param _amount The number of tokens to mint.
    /// @return True on success.
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        require(_to != address(0), Stabletoken__ZeroAddress());
        require(_amount >= 0, Stabletoken__ZeroAmount());

        _mint(_to, _amount);
        return true;
    }
}
