// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Importing OpenZeppelin contracts for access control, pausability, and ERC1155 functionality
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// Shared1155Token contract combining ERC1155, access control, and custom functionality for NFT and ERC20 management
contract Shared1155Token is AccessControl, Pausable, ERC1155, ERC1155Burnable, ERC1155URIStorage, ERC1155Supply, IERC1155Receiver {
    // Using OpenZeppelin's Counters library for incrementing token and collection IDs
    using Counters for Counters.Counter;

    // Role identifiers for minter and collection creator
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant COLLECTION_CREATOR_ROLE = keccak256("COLLECTION_CREATOR_ROLE");

    // Counters for generating unique token and collection IDs
    Counters.Counter private _tokenIdCounter;
    Counters.Counter private _collectionIdCounter;

    // Name of the contract, set to "Carbon Credit Asset"
    string public name;

    // Mapping from collection ID to Collection struct
    mapping(uint256 => Collection) public collections;
    // Mapping from token ID to CollectionData struct
    mapping(uint256 => CollectionData) public collectionDatas;
    // Array of all collection IDs
    uint256[] public collectionIds;
    // Array of all token IDs
    uint256[] public tokenIds;
    // Array of stored data strings
    string[] public storedData;

    // Mapping from token ID to array of transfer records for tracking transfer history
    mapping(uint256 => TransferRecord[]) public transferHistory;

    // Event emitted when a new NFT is minted with a collection URI
    event CollectionURIMinted(
        address indexed account, // Address that received the minted NFT
        uint256 tokenId,        // Token ID of the minted NFT
        bytes32 collectionURI,  // Content identifier (CID) for the collection
        uint256 amount          // Amount of tokens minted
    );

    // Event emitted when a new collection is created
    event CollectionCreated(
        uint256 indexed collectionId, // ID of the created collection
        string suffix                // Suffix associated with the collection
    );

    // Event emitted when a collection is deleted
    event CollectionDeleted(
        uint256 indexed collectionId, // ID of the deleted collection
        string suffix                // Suffix of the deleted collection
    );

    // Event emitted when an operator is approved or revoked for contract-owned NFTs
    event OperatorApprovedForContractNFTs(
        address indexed operator, // Operator address
        bool approved             // Approval status (true for approved, false for revoked)
    );

    // Event emitted when data is stored in the contract
    event DataStored(
        address indexed account, // Address that stored the data
        string data             // Stored data string
    );

    // Event emitted when data is deleted from the contract
    event DataDeleted(
        address indexed account, // Address that deleted the data
        string data             // Deleted data string
    );

    // Event emitted when an NFT transfer is recorded
    event TransferRecorded(
        uint256 indexed tokenId, // Token ID of the transferred NFT
        address indexed from,   // Sender address
        address indexed to,     // Recipient address
        uint256 amount,         // Amount of tokens transferred
        uint256 timestamp       // Timestamp of the transfer
    );

    // Event emitted when ERC20 tokens are transferred from the contract
    event ContractERC20Transferred(
        address indexed tokenAddress, // Address of the ERC20 token contract
        address indexed to,           // Recipient address
        uint256 amount,              // Amount of tokens transferred
        uint256 timestamp            // Timestamp of the transfer
    );

    // Struct to represent a collection
    struct Collection {
        uint256 id;     // Unique identifier for the collection
        string suffix;  // Suffix associated with the collection
    }

    // Struct to store collection data for a token
    struct CollectionData {
        bytes32 cid;         // Content identifier (CID) for the collection
        uint256 collectionId; // ID of the associated collection
    }

    // Struct to represent details of an NFT
    struct NFTDetails {
        uint256 tokenId;            // Token ID of the NFT
        uint256 amount;             // Amount of tokens
        string uri;                 // URI of the NFT
        CollectionData collectionData; // Associated collection data
    }

    // Struct to store transfer history for an NFT
    struct TransferRecord {
        address from;     // Sender address
        address to;       // Recipient address
        uint256 amount;   // Amount of tokens transferred
        uint256 timestamp; // Timestamp of the transfer
    }

    // Constructor: Initializes the contract and grants roles to the deployer
    constructor() ERC1155("") {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender()); // Grant admin role to deployer
        _grantRole(MINTER_ROLE, _msgSender());       // Grant minter role to deployer
        _grantRole(COLLECTION_CREATOR_ROLE, _msgSender()); // Grant collection creator role to deployer
        name = "Carbon Credit Asset";                // Set contract name
        _setApprovalForAll(address(this), address(this), true); // Approve contract to manage its own NFTs
    }

    // Internal function to normalize input strings, converting hex strings (starting with "0x") to UTF-8
    function _normalizeString(string memory input) private pure returns (string memory) {
        if (bytes(input).length >= 2 && bytes(input)[0] == '0' && bytes(input)[1] == 'x') {
            bytes memory inputBytes = bytes(input);
            bytes memory hexBytes = new bytes(inputBytes.length - 2);
            for (uint256 i = 0; i < inputBytes.length - 2; i++) {
                hexBytes[i] = inputBytes[i + 2];
            }
            return string(abi.decode(hexBytes, (string)));
        }
        return input;
    }

    // Override supportsInterface to include IERC1155Receiver interface
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, AccessControl, ERC1155) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    // Override uri to return the token URI from ERC1155URIStorage
    function uri(uint256 tokenId) public view override(ERC1155, ERC1155URIStorage) returns (string memory) {
        return super.uri(tokenId);
    }

    // Set the URI for a specific token, restricted to admin role
    function setTokenURI(uint256 tokenId, string memory newURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(totalSupply(tokenId) > 0, "Shared1155Token: URI set of nonexistent token");
        _setURI(tokenId, _normalizeString(newURI));
    }

    // Pause the contract, restricted to admin role
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    // Unpause the contract, restricted to admin role
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // Mint new tokens, restricted to minter role
    function mint(address account, uint256 id, uint256 amount, bytes memory data) external onlyRole(MINTER_ROLE) {
        _mint(account, id, amount, data);
    }

    // Create a new collection with a unique suffix, restricted to collection creator role
    function createCollection(string memory suffix) external onlyRole(COLLECTION_CREATOR_ROLE) {
        string memory normalizedSuffix = _normalizeString(suffix);
        for (uint256 i = 0; i < collectionIds.length; i++) {
            uint256 id = collectionIds[i];
            if (keccak256(bytes(collections[id].suffix)) == keccak256(bytes(normalizedSuffix))) {
                revert("Shared1155Token: Duplicate suffix detected");
            }
        }

        _collectionIdCounter.increment();
        uint256 collectionId = _collectionIdCounter.current();

        collections[collectionId] = Collection(collectionId, normalizedSuffix);
        collectionIds.push(collectionId);
        emit CollectionCreated(collectionId, normalizedSuffix);
    }

    // Mint an NFT and associate it with a collection, restricted to minter role
    function safeCast(
        string memory tokenURI,
        uint256 amount,
        bytes32 cid,
        string memory suffix
    ) external onlyRole(MINTER_ROLE) {
        string memory normalizedSuffix = _normalizeString(suffix);
        string memory normalizedTokenURI = _normalizeString(tokenURI);
        uint256 collectionId = 0;
        for (uint256 i = 0; i < collectionIds.length; i++) {
            if (keccak256(bytes(collections[collectionIds[i]].suffix)) == keccak256(bytes(normalizedSuffix))) {
                collectionId = collections[collectionIds[i]].id;
                break;
            }
        }
        require(collectionId != 0, "Shared1155Token: Collection with suffix does not exist");

        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();

        _mint(address(this), tokenId, amount, "");
        _setURI(tokenId, normalizedTokenURI);

        CollectionData storage collectionData = collectionDatas[tokenId];
        collectionData.cid = cid;
        collectionData.collectionId = collectionId;

        tokenIds.push(tokenId);

        emit CollectionURIMinted(address(this), tokenId, cid, amount);
    }

    // Mint multiple tokens in a batch, restricted to minter role
    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) external onlyRole(MINTER_ROLE) {
        _mintBatch(to, ids, amounts, data);
    }

    // Override _update to record transfer history when NFTs are transferred
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply) whenNotPaused {
        super._update(from, to, ids, values);

        for (uint256 i = 0; i < ids.length; i++) {
            if (values[i] > 0) {
                transferHistory[ids[i]].push(TransferRecord({
                    from: from,
                    to: to,
                    amount: values[i],
                    timestamp: block.timestamp
                }));
                emit TransferRecorded(ids[i], from, to, values[i], block.timestamp);
            }
        }
    }

    // Get collection data for a specific token
    function getCollectionData(uint256 tokenId) external view returns (CollectionData memory) {
        require(totalSupply(tokenId) > 0, "Shared1155Token: Nonexistent token");
        return collectionDatas[tokenId];
    }

    // Get details of a specific collection
    function getCollection(uint256 collectionId) external view returns (Collection memory) {
        require(collections[collectionId].id != 0, "Shared1155Token: Collection does not exist");
        return collections[collectionId];
    }

    // Get all collections
    function getAllCollections() external view returns (Collection[] memory) {
        Collection[] memory allCollections = new Collection[](collectionIds.length);
        for (uint256 i = 0; i < collectionIds.length; i++) {
            allCollections[i] = collections[collectionIds[i]];
        }
        return allCollections;
    }

    // Get collection data for all tokens
    function getAllCollectionDatas() external view returns (CollectionData[] memory) {
        CollectionData[] memory allDatas = new CollectionData[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            allDatas[i] = collectionDatas[tokenIds[i]];
        }
        return allDatas;
    }

    // Grant a role to an account, restricted to admin role
    function grantRoleTo(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(role, account);
    }

    // Get the suffix of a specific collection
    function getCollectionSuffix(uint256 collectionId) external view returns (string memory) {
        require(collections[collectionId].id != 0, "Shared1155Token: Collection does not exist");
        return collections[collectionId].suffix;
    }

    // Delete a collection by its suffix, restricted to admin role
    function deleteCollectionBySuffix(string memory suffix) external onlyRole(DEFAULT_ADMIN_ROLE) {
        string memory normalizedSuffix = _normalizeString(suffix);
        for (uint256 i = 0; i < collectionIds.length; i++) {
            uint256 id = collectionIds[i];
            if (keccak256(bytes(collections[id].suffix)) == keccak256(bytes(normalizedSuffix))) {
                delete collections[id];
                if (i < collectionIds.length - 1) {
                    collectionIds[i] = collectionIds[collectionIds.length - 1];
                }
                collectionIds.pop();
                emit CollectionDeleted(id, normalizedSuffix);
                return;
            }
        }
        revert("Shared1155Token: Collection with suffix not found");
    }

    // Approve or revoke an operator for contract-owned NFTs
    function approveOperatorForContractNFTs(address operator, bool approved) external {
        require(operator != address(0), "Shared1155Token: Invalid operator address");
        _setApprovalForAll(address(this), operator, approved);
        emit OperatorApprovedForContractNFTs(operator, approved);
    }

    // Check if an operator is approved for contract-owned NFTs
    function isOperatorApprovedForContractNFTs() external view returns (bool) {
        return isApprovedForAll(address(this), msg.sender);
    }

    // Store arbitrary data, restricted to admin role
    function storeData(string memory data) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bytes(data).length > 0, "Shared1155Token: Data cannot be empty");
        storedData.push(data);
        emit DataStored(msg.sender, data);
    }

    // Get all stored data
    function getAllStoredData() external view returns (string[] memory) {
        return storedData;
    }

    // Delete stored data by value, restricted to admin role
    function deleteDataByValue(string memory data) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bytes(data).length > 0, "Shared1155Token: Data cannot be empty");
        for (uint256 i = 0; i < storedData.length; i++) {
            if (keccak256(bytes(storedData[i])) == keccak256(bytes(data))) {
                storedData[i] = storedData[storedData.length - 1];
                storedData.pop();
                emit DataDeleted(msg.sender, data);
                return;
            }
        }
        revert("Shared1155Token: Data not found");
    }

    // Transfer ERC20 tokens from the caller and an NFT from the contract
    function transferERC20(
        address tokenAddress,
        address to,
        uint256 amount,
        string memory targetURI
    ) external {
        require(to != address(0), "Shared1155Token: Invalid recipient address");
        require(amount > 0, "Shared1155Token: Transfer amount must be greater than 0");
        IERC20 token = IERC20(tokenAddress);
        require(token.balanceOf(msg.sender) >= amount, "Shared1155Token: Insufficient ERC20 balance");
        require(token.allowance(msg.sender, address(this)) >= amount, "Shared1155Token: Insufficient ERC20 allowance");
        token.transferFrom(msg.sender, to, amount);

        string memory normalizedTargetURI = _normalizeString(targetURI);
        uint256 tokenId = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (keccak256(bytes(uri(tokenIds[i]))) == keccak256(bytes(normalizedTargetURI))) {
                tokenId = tokenIds[i];
                break;
            }
        }
        require(tokenId != 0, "Shared1155Token: NFT with specified URI does not exist");
        require(balanceOf(address(this), tokenId) >= 1, "Shared1155Token: Insufficient NFT balance");

        safeTransferFrom(address(this), msg.sender, tokenId, 1, "");
    }

    // Transfer ERC20 tokens held by the contract, restricted to collection creator role
    function moveContractERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) external onlyRole(COLLECTION_CREATOR_ROLE) {
        require(to != address(0), "Shared1155Token: Invalid recipient address");
        require(amount > 0, "Shared1155Token: Transfer amount must be greater than 0");
        IERC20 token = IERC20(tokenAddress);
        require(token.balanceOf(address(this)) >= amount, "Shared1155Token: Insufficient contract ERC20 balance");
        token.transfer(to, amount);
        emit ContractERC20Transferred(tokenAddress, to, amount, block.timestamp);
    }

    // Get details of NFTs held by the contract
    function getContractNFTs() external view returns (NFTDetails[] memory) {
        uint256 validCount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (balanceOf(address(this), tokenIds[i]) > 0) {
                validCount++;
            }
        }

        NFTDetails[] memory nfts = new NFTDetails[](validCount);
        uint256 index = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 amount = balanceOf(address(this), tokenId);
            if (amount > 0) {
                nfts[index] = NFTDetails({
                    tokenId: tokenId,
                    amount: amount,
                    uri: uri(tokenId),
                    collectionData: collectionDatas[tokenId]
                });
                index++;
            }
        }

        return nfts;
    }

    // Handle receipt of a single ERC1155 token
    function onERC1155Received(
        address /* operator */, // Unused parameter
        address /* from */,     // Unused parameter
        uint256 /* id */,      // Unused parameter
        uint256 /* value */,   // Unused parameter
        bytes calldata /* data */ // Unused parameter
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    // Handle receipt of multiple ERC1155 tokens
    function onERC1155BatchReceived(
        address /* operator */, // Unused parameter
        address /* from */,     // Unused parameter
        uint256[] calldata /* ids */, // Unused parameter
        uint256[] calldata /* values */, // Unused parameter
        bytes calldata /* data */ // Unused parameter
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    // Transfer an NFT from the contract by URI, restricted to admin role
    function transferNFTByURI(
        address to,
        string memory targetURI,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Shared1155Token: Invalid recipient address");
        require(amount > 0, "Shared1155Token: Transfer amount must be greater than 0");

        string memory normalizedTargetURI = _normalizeString(targetURI);
        uint256 tokenId = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (keccak256(bytes(uri(tokenIds[i]))) == keccak256(bytes(normalizedTargetURI))) {
                tokenId = tokenIds[i];
                break;
            }
        }
        require(tokenId != 0, "Shared1155Token: NFT with specified URI does not exist");
        require(balanceOf(address(this), tokenId) >= amount, "Shared1155Token: Insufficient NFT balance");

        safeTransferFrom(address(this), to, tokenId, amount, "");
    }

    // Get NFTs owned by a specific account
    function NFTList(address account) external view returns (NFTDetails[] memory) {
        require(account != address(0), "Shared1155Token: Invalid account address");

        uint256 validCount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (balanceOf(account, tokenIds[i]) > 0) {
                validCount++;
            }
        }

        NFTDetails[] memory nfts = new NFTDetails[](validCount);
        uint256 index = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 amount = balanceOf(account, tokenId);
            if (amount > 0) {
                nfts[index] = NFTDetails({
                    tokenId: tokenId,
                    amount: amount,
                    uri: uri(tokenId),
                    collectionData: collectionDatas[tokenId]
                });
                index++;
            }
        }
        
        return nfts;
    }

    // Get NFTs owned by the caller
    function getUser_NFTList() external view returns (NFTDetails[] memory) {
        address account = msg.sender;

        uint256 validCount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (balanceOf(account, tokenIds[i]) > 0) {
                validCount++;
            }
        }

        NFTDetails[] memory nfts = new NFTDetails[](validCount);
        uint256 index = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 amount = balanceOf(account, tokenId);
            if (amount > 0) {
                nfts[index] = NFTDetails({
                    tokenId: tokenId,
                    amount: amount,
                    uri: uri(tokenId),
                    collectionData: collectionDatas[tokenId]
                });
                index++;
            }
        }

        return nfts;
    }

    // Get transfer history for a specific token
    function getTransferHistory(uint256 tokenId) external view returns (TransferRecord[] memory) {
        require(totalSupply(tokenId) > 0, "Shared1155Token: Nonexistent token");
        return transferHistory[tokenId];
    }
}