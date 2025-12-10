// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IBaseRegistrar
 * @notice Interface for ENS BaseRegistrarImplementation
 * @dev Minimal interface for methods used by DAOETHRegistrarController
 */
interface IBaseRegistrar {
    /**
     * @notice Check if a name is available for registration
     * @param id The token ID (labelhash as uint256)
     * @return True if the name is available
     */
    function available(uint256 id) external view returns (bool);

    /**
     * @notice Register a name
     * @param id The token ID (labelhash as uint256)
     * @param owner The owner of the name
     * @param duration The registration duration in seconds
     * @return The expiry timestamp
     */
    function register(
        uint256 id,
        address owner,
        uint256 duration
    ) external returns (uint256);

    /**
     * @notice Transfer a name
     * @param from The current owner
     * @param to The new owner
     * @param tokenId The token ID
     */
    function transferFrom(address from, address to, uint256 tokenId) external;
}

