pragma solidity 0.6.6;

import {ERC721} from "./ERC721.sol";
import {AccessControlMixin} from "../../../common/AccessControlMixin.sol";
import {IChildToken} from "../IChildToken.sol";
import {NativeMetaTransaction} from "../../../common/NativeMetaTransaction.sol";
import {ContextMixin} from "../../../common/ContextMixin.sol";

contract ChildERC721 is
    ERC721,
    IChildToken,
    AccessControlMixin,
    NativeMetaTransaction,
    ContextMixin
{
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    // limit batching of tokens due to gas limit restrictions
    uint256 public constant BATCH_LIMIT = 20;

    event WithdrawnBatch(address indexed user, uint256[] tokenIds);
    event TransferWithMetadata(address indexed from, address indexed to, uint256 indexed tokenId, bytes metaData);

    constructor() public ERC721("", "") {}

    /**
     * @notice Initialize the contract after it has been proxified
     * @dev meant to be called once immediately after deployment
     */
    function initialize(
        string calldata name_,
        string calldata symbol_,
        address childChainManager
    )
        external
        initializer
    {
        setName(name_);
        setSymbol(symbol_);
        _setupContractId(string(abi.encodePacked("Child", symbol_)));
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(DEPOSITOR_ROLE, childChainManager);
        _initializeEIP712(name_);
    }

    // This is to support Native meta transactions
    // never use msg.sender directly, use _msgSender() instead
    function _msgSender()
        internal
        override
        view
        returns (address payable sender)
    {
        return ContextMixin.msgSender();
    }

    /**
     * @notice called when token is deposited on root chain
     * @dev Should be callable only by ChildChainManager
     * Should handle deposit by minting the required tokenId for user
     * Make sure minting is done only by this function
     * @param user user address for whom deposit is being done
     * @param depositData abi encoded tokenId
     */
    function deposit(address user, bytes calldata depositData)
        external
        override
        only(DEPOSITOR_ROLE)
    {
        // deposit single
        if (depositData.length == 32) {
            uint256 tokenId = abi.decode(depositData, (uint256));
            _mint(user, tokenId);

        // deposit batch
        } else {
            uint256[] memory tokenIds = abi.decode(depositData, (uint256[]));
            uint256 length = tokenIds.length;
            for (uint256 i; i < length; i++) {
                _mint(user, tokenIds[i]);
            }
        }
    }

    /**
     * @notice called when user wants to withdraw token back to root chain
     * @dev Should burn user's token. This transaction will be verified when exiting on root chain
     * @param tokenId tokenId to withdraw
     */
    function withdraw(uint256 tokenId) external {
        require(_msgSender() == ownerOf(tokenId), "ChildERC721: INVALID_TOKEN_OWNER");
        _burn(tokenId);
    }

    /**
     * @notice called when user wants to withdraw multiple tokens back to root chain
     * @dev Should burn user's tokens. This transaction will be verified when exiting on root chain
     * @param tokenIds tokenId list to withdraw
     */
    function withdrawBatch(uint256[] calldata tokenIds) external {
        uint256 length = tokenIds.length;
        require(length <= BATCH_LIMIT, "ChildERC721: EXCEEDS_BATCH_LIMIT");
        for (uint256 i; i < length; i++) {
            uint256 tokenId = tokenIds[i];
            require(_msgSender() == ownerOf(tokenId), string(abi.encodePacked("ChildERC721: INVALID_TOKEN_OWNER ", tokenId)));
            _burn(tokenId);
        }
        emit WithdrawnBatch(_msgSender(), tokenIds);
    }

    /**
     * @notice called when user wants to withdraw token back to root chain with arbitrary metadata
     * @dev Should handle withraw by burning user's token.
     * 
     * This transaction will be verified when exiting on root chain
     *
     * @param tokenId tokenId to withdraw
     */
    function withdrawWithMetadata(uint256 tokenId) external {

        require(_msgSender() == ownerOf(tokenId), "ChildERC721: INVALID_TOKEN_OWNER");

        // Encoding metadata associated with tokenId & emitting event
        emit TransferWithMetadata(_msgSender(), address(0), tokenId, this.encodeTokenMetadata(tokenId));

        _burn(tokenId);

    }

    /**
     * @notice This method is supposed to be called by client when withdrawing token with metadata
     * and pass return value of this function as second paramter of `withdrawWithMetadata` method
     *
     * It can be overridden by clients to encode data in a different form, which needs to
     * be decoded back by them correctly during exiting
     *
     * @param tokenId Token for which URI to be fetched
     */
    function encodeTokenMetadata(uint256 tokenId) external view virtual returns (bytes memory) {

        // You're always free to change this default implementation
        // and pack more data in byte array which can be decoded back
        // in L1
        return abi.encode(tokenURI(tokenId));

    }
}
