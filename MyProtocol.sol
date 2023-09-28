// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "contracts/Module2_Practice/contracts/Module2_Practice/Vault.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/*Задание

Создать один проект из нескольких контрактов, в которых будут выполнены следующие требования:

1. Пользователи смогут покупать ваш токен (токен ERC20 вашего протокола) за USDT, USDC, DAI или Эфир. При этом, ваш протокол должен будет брать комиссию в 10% от общей суммы покупки. Например, покупатель хочет купить 10 myToken за 100 USDC, ему потребуется заплатить 110 USDC для этой покупки. 

2. 10% от покупок вашего токена должны перечисляться на другой контракт для хранения. Для удобства, его можно назвать Treasury или Vault. 

3. Также пользователи могут просто делать вложения в контракт Vault тех же токенов (USDC, USDT, DAI...), за это им будет выдан 1 NFT, как чек за депозит. 

4. Позже пользователи должны иметь возможность вернуть свой NFT и получить назад депозит плюс 2% от токенов, которые были перенесены сюда после покупки myToken (тех 10% сверх).
*/

/// Контракт токена, который покупает пользователь
/// MINTER_ROLE передаётся контракту протокола MyProtocol
contract MyToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC20("MyToken", "MTK") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}

/// Основной контракт протокола. Пользователь взаимодействует с контрактом
/// для покупки токенов MyToken и вывода средств (в т.ч. из хранилища MyVault)
contract MyProtocol is Ownable{

    /// Событие испускается при успешной покупке токена MyToken
    event TokenBuy(address boughtBy);
    /// Событие испускается при успешном внесении адреса токена в разрешённый список
    event TokenWhitelisted(address tokenAddr);
    /// Событие испускается при успешном выводе средств
    event Payout(address);

    /// Список разрешённых токенов
    mapping (address => bool) eligibleTokens;
    /// Список покупок токена MyToken
    mapping (address => uint) addrToBoughtAmount;
    
    /// Токена MyToken
    MyToken public myToken;
    /// Хранилище MyVault
    Vault private vault;
    /// NFT-токен MTKShare
    MTKShare public mtkshare;
    /// Текущий курс ETH
    uint private currentEthRate;

    constructor(address _vault, 
                uint256 _currentEthRate, 
                address[] memory _eligibleTokensArr, 
                address _myToken,
                address _mtkshare) {
        for (uint i = 0; i < _eligibleTokensArr.length; i++) {
            eligibleTokens[_eligibleTokensArr[i]] = true;
        }
        vault = Vault(payable(_vault));
        currentEthRate = _currentEthRate;
        myToken = MyToken(_myToken);
        mtkshare = MTKShare(_mtkshare);
    }

    /// Вносит адрес токена в список разрешённых токенов
    function whitelist(address _tokenAddr) public onlyOwner {
        eligibleTokens[_tokenAddr] = true;
        emit TokenWhitelisted(_tokenAddr);
    }

    /// Позволяет пользователю приобрести токен MyToken за стейблкоины из списка разрешённых.
    /// Комиссия 10% от суммы покупки отправляется в контракт-хранилище Vault;
    function buyWithStablecoin(uint256 amount, address stablecoinAddr) public {
        require(stablecoinAddr != address(0));
        ERC20 stablecoin = ERC20(stablecoinAddr);
        require(eligibleTokens[stablecoinAddr], "Token is not eligible");
        require(stablecoin.transferFrom(msg.sender, address(this), amount * 9 / 10), "Token transferring failure");
        vault.deposit(amount / 10, stablecoinAddr);
        myToken.mint(msg.sender, amount * 9 / 10);
        emit TokenBuy(msg.sender);
    }

    /// Выводит все внесённые ранее токены stableCoinAddr пользователя + 2% от комиссионных 10%,
    /// если пользователь ранее покупал токен MyToken.
    /// stableCoinAddr = 0, если депозит в ETH.
    function getBackDeposit(uint _tokenId, address stableCoinAddr) public {
        require(msg.sender == mtkshare.ownerOf(_tokenId), "You are not the owner");
        uint amount = vault.getDeposits(_tokenId, stableCoinAddr);
        require(amount > 0, "Deposit has been withdrawn or not found");
        amount += vault.getCommissions(msg.sender, stableCoinAddr) * 2 / 100;
        mtkshare.safeTransferFrom(msg.sender, address(vault), _tokenId);
        vault.payout(amount, _tokenId, stableCoinAddr);
        emit Payout(msg.sender);
    }

    /// Покупка токенов MyToken за ETH.
    /// 10% от суммы покупки отправляется в Vault.
    receive() payable external {
        require(msg.value > 0, "Cannot be zero");
        (bool sent, ) = address(vault).call{value: msg.value / 10}("");
        require(sent, "Failed to send Ether to Vault");
        //addrToBoughtAmountByEth[msg.sender] = msg.value * 9 / 10 * currentEthRate;
        myToken.mint(msg.sender, msg.value * 9 / 10);
        emit TokenBuy(msg.sender);
    }
}