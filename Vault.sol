// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import "contracts/Module2_Practice/contracts/Module2_Practice/MyProtocol.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

/// Контракт NFT-токена, который является подтверждением внесения средств в контракт-хранилище MyVault.
/// MINTER_ROLE передаётся контракту-хранилищу MyVault;
contract MTKShare is ERC721, ERC721Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC721("MTKShare", "MTKS") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function safeMint(address to, uint256 tokenId) public onlyRole(MINTER_ROLE) {
        _safeMint(to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

/// Контракт-хранилище средств. Чеканит NFT-чек при внесении средств в контракт.
contract Vault is Ownable {

    /// Событие сипускается при внесении адреса токена в список разрешённых
    event TokenWhitelisted(address tokenAddr);

    /// NFT-токен MTKShare
    MTKShare public mtkshare;
    /// Протокол MyProtocol
    MyProtocol private myProtocol;

    /// Идентификатор NFT-чека
    uint256 tokenId = 0;
    /// Депозиты пользователей по идентификатору NFT
    /// NFT_ID => (user address => amount)
    mapping(uint => mapping (address => uint)) public deposits;
    /// Комиссии пользователей за покупку токенов 
    /// User_address => (stablecoin_address => amount)
    mapping(address => mapping (address => uint)) public commissions;
    /// Разрешённые токены
    mapping (address => bool) public eligibleTokens;

    constructor(address[] memory _eligibleTokensArr, address _mtkshare) {
        for (uint i = 0; i < _eligibleTokensArr.length; i++) {
            eligibleTokens[_eligibleTokensArr[i]] = true;
        }

        mtkshare = MTKShare(_mtkshare);
    }

    /// Устанавливает адрес протокола. 
    function setMyProtocol(address _address) public onlyOwner {
        require(_address != address(0), "Not zero address");
        myProtocol = MyProtocol(payable(_address));
    }

    /// Внесение в список разрешённых токенов
    function whitelist(address _tokenAddr) public onlyOwner {
        eligibleTokens[_tokenAddr] = true;
        emit TokenWhitelisted(_tokenAddr);
    }

    /// Депозит средств в контракт. 
    /// Вызывается, как пользователем (депозит), так и протоколом (комиссии)
    function deposit(uint256 amount, address stablecoinAddr) public {
        require(amount > 0, "Zero is not acceptable");
        require(eligibleTokens[stablecoinAddr], "Token is not eligible");
        if (msg.sender == address(myProtocol)) {
            require(IERC20(stablecoinAddr).transferFrom(tx.origin, address(this), amount),
            "Token transferring while deposit failure");
            commissions[tx.origin][stablecoinAddr] = amount;
        }
        else {
            require(IERC20(stablecoinAddr).transferFrom(msg.sender, address(this), amount), 
            "Token transferring while deposit failure");
            mtkshare.safeMint(msg.sender, tokenId);
            deposits[tokenId][stablecoinAddr] = amount;
        }
        tokenId++;
    }

    /// Внесение ETH в хранилище.
    /// Логика при внесении пользователем (депозит) отличается от логики внесения протоколом
    /// (комиссии)
    receive() payable external {
        require(msg.value > 0, "Cannot be zero");
        if (msg.sender == address(myProtocol)) {
            commissions[tx.origin][address(0)] = msg.value;
        }
        else {
            mtkshare.safeMint(msg.sender, tokenId);
            deposits[tokenId][address(0)] = msg.value;
            tokenId++;
        }
    }

    /// Смотри ERC165
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
    
    /// Возвращает сумму депозита
    function getDeposits(uint _tokenId, address stableCoinAddr) public view returns (uint) {
        return deposits[_tokenId][stableCoinAddr];
    }

    /// Возвращает сумму комиссии
    function getCommissions(address sender, address stableCoinAddr) public view returns (uint) {
        return commissions[sender][stableCoinAddr];
  }

    /// Выводит все средства (в токенах stableCoinAddr) пользователя.
    /// stableCoinAddr = address(0) для ETH
    /// (!) Может быть вызвана только контрактов протокола MyProtocol
   function payout(uint amount, uint _tokenId, address stableCoinAddr) public {
       require(msg.sender == address(myProtocol), "you are not allowed");
       mtkshare.burn(_tokenId);
       commissions[tx.origin][stableCoinAddr] -= amount;
       if (stableCoinAddr == address(0)) {
           (bool sent, ) = tx.origin.call{value: amount}("");
           require(sent, "ETH payout failure");
       }
       else {
           IERC20(stableCoinAddr).transfer(tx.origin, amount);
        }
   }
}