// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IMarketEscrow {
    enum AssetType { ERC20, ERC721, ERC1155 }
    enum LoanState { Inactive, Active, Extended, Completed, Defaulted }
}

contract MortgageSettings {
    uint256 public constant MIN_DOWNPAYMENT = 3;
    uint256 public constant MAX_DOWNPAYMENT = 85;
    uint256 public constant MIN_DURATION = 365 days;
    uint256 public constant MAX_DURATION = 5475 days;
    uint256 public constant DEFAULT_FEE = 25;
    
    address public owner;
    mapping(address => bool) public marketplaces;
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    
    function setMarketplace(address market, bool status) external onlyOwner {
        marketplaces[market] = status;
    }
    
    function getInterestRate(uint256 duration) public pure returns (uint256) {
        if (duration <= 365 days) return 25;
        if (duration <= 1825 days) return 45;
        return 70;
    }
}

contract ERC20Escrow is IMarketEscrow {
    struct LoanCore {
        address seller;
        address buyer;
        address token;
        uint256 amount;
        LoanState state;
    }
    
    struct LoanTerms {
        uint256 downPayment;
        uint256 loanAmount;
        uint256 duration;
        uint256 startTime;
        uint256 totalRepaid;
        uint256 interestRate;
        uint8 extensions;
    }
    
    mapping(uint256 => LoanCore) public loans;
    mapping(uint256 => LoanTerms) public terms;
    uint256 public loanCount;
    MortgageSettings public settings;
    
    constructor(address _settings) {
        settings = MortgageSettings(_settings);
    }
    
    function createLoan(
        address token,
        uint256 amount,
        uint256 downPaymentPercent,
        uint256 duration
    ) external returns (uint256 loanId) {
        require(settings.marketplaces(msg.sender));
        require(downPaymentPercent >= settings.MIN_DOWNPAYMENT());
        require(downPaymentPercent <= settings.MAX_DOWNPAYMENT());
        require(duration >= settings.MIN_DURATION());
        require(duration <= settings.MAX_DURATION());
        
        loanId = ++loanCount;
        uint256 downPayment = (amount * downPaymentPercent) / 100;
        
        loans[loanId] = LoanCore({
            seller: tx.origin,
            buyer: address(0),
            token: token,
            amount: amount,
            state: LoanState.Inactive
        });
        
        terms[loanId] = LoanTerms({
            downPayment: downPayment,
            loanAmount: amount - downPayment,
            duration: duration,
            startTime: 0,
            totalRepaid: 0,
            interestRate: settings.getInterestRate(duration),
            extensions: 0
        });
    }
    
    function startLoan(uint256 loanId) external payable {
        LoanCore storage loan = loans[loanId];
        LoanTerms storage term = terms[loanId];
        require(loan.state == LoanState.Inactive);
        require(msg.value >= term.downPayment);
        
        loan.buyer = msg.sender;
        loan.state = LoanState.Active;
        term.startTime = block.timestamp;
        
        IERC20(loan.token).transferFrom(loan.seller, address(this), loan.amount);
    }
    
    function makePayment(uint256 loanId) external payable {
        LoanCore storage loan = loans[loanId];
        LoanTerms storage term = terms[loanId];
        require(loan.state == LoanState.Active || loan.state == LoanState.Extended);
        require(msg.sender == loan.buyer);
        
        term.totalRepaid += msg.value;
        
        if (term.totalRepaid >= _getTotalDue(term)) {
            _completeLoan(loanId);
        }
    }
    
    function extendLoan(uint256 loanId) external {
        LoanCore storage loan = loans[loanId];
        LoanTerms storage term = terms[loanId];
        require(loan.state == LoanState.Active);
        require(term.extensions < 3);
        require(term.totalRepaid >= term.loanAmount / 2);
        
        term.duration += 30 days;
        term.extensions++;
        loan.state = LoanState.Extended;
    }
    
    function defaultLoan(uint256 loanId) external {
        LoanCore storage loan = loans[loanId];
        LoanTerms storage term = terms[loanId];
        require(block.timestamp > term.startTime + term.duration);
        require(loan.state == LoanState.Active || loan.state == LoanState.Extended);
        
        uint256 fee = (term.downPayment * settings.DEFAULT_FEE()) / 1000;
        
        loan.state = LoanState.Defaulted;
        IERC20(loan.token).transfer(loan.seller, loan.amount);
        payable(loan.seller).transfer(fee);
        payable(loan.buyer).transfer(term.totalRepaid - fee);
    }
    
    function _getTotalDue(LoanTerms memory term) internal pure returns (uint256) {
        return term.loanAmount + ((term.loanAmount * term.interestRate * (term.duration + term.extensions * 30 days)) / (365 days * 1000));
    }
    
    function _completeLoan(uint256 loanId) internal {
        LoanCore storage loan = loans[loanId];
        LoanTerms storage term = terms[loanId];
        loan.state = LoanState.Completed;
        IERC20(loan.token).transfer(loan.buyer, loan.amount);
        payable(loan.seller).transfer(term.totalRepaid);
    }
    
    function getTotalDue(uint256 loanId) external view returns (uint256) {
        return _getTotalDue(terms[loanId]);
    }
}

contract ERC721Escrow is IMarketEscrow {
    struct LoanCore {
        address seller;
        address buyer;
        address nft;
        uint256 tokenId;
        uint256 amount;
        LoanState state;
    }
    
    struct LoanTerms {
        uint256 downPayment;
        uint256 loanAmount;
        uint256 duration;
        uint256 startTime;
        uint256 totalRepaid;
        uint256 interestRate;
        uint8 extensions;
    }
    
    mapping(uint256 => LoanCore) public loans;
    mapping(uint256 => LoanTerms) public terms;
    uint256 public loanCount;
    MortgageSettings public settings;
    
    constructor(address _settings) {
        settings = MortgageSettings(_settings);
    }
    
    function createLoan(
        address nft,
        uint256 tokenId,
        uint256 amount,
        uint256 downPaymentPercent,
        uint256 duration
    ) external returns (uint256 loanId) {
        require(settings.marketplaces(msg.sender));
        require(downPaymentPercent >= settings.MIN_DOWNPAYMENT());
        require(downPaymentPercent <= settings.MAX_DOWNPAYMENT());
        require(duration >= settings.MIN_DURATION());
        require(duration <= settings.MAX_DURATION());
        
        loanId = ++loanCount;
        uint256 downPayment = (amount * downPaymentPercent) / 100;
        
        loans[loanId] = LoanCore({
            seller: tx.origin,
            buyer: address(0),
            nft: nft,
            tokenId: tokenId,
            amount: amount,
            state: LoanState.Inactive
        });
        
        terms[loanId] = LoanTerms({
            downPayment: downPayment,
            loanAmount: amount - downPayment,
            duration: duration,
            startTime: 0,
            totalRepaid: 0,
            interestRate: settings.getInterestRate(duration),
            extensions: 0
        });
    }
    
    function startLoan(uint256 loanId) external payable {
        LoanCore storage loan = loans[loanId];
        LoanTerms storage term = terms[loanId];
        require(loan.state == LoanState.Inactive);
        require(msg.value >= term.downPayment);
        
        loan.buyer = msg.sender;
        loan.state = LoanState.Active;
        term.startTime = block.timestamp;
        
        IERC721(loan.nft).transferFrom(loan.seller, address(this), loan.tokenId);
    }
    
    function makePayment(uint256 loanId) external payable {
        LoanCore storage loan = loans[loanId];
        LoanTerms storage term = terms[loanId];
        require(loan.state == LoanState.Active || loan.state == LoanState.Extended);
        require(msg.sender == loan.buyer);
        
        term.totalRepaid += msg.value;
        
        if (term.totalRepaid >= _getTotalDue(term)) {
            _completeLoan(loanId);
        }
    }
    
    function extendLoan(uint256 loanId) external {
        LoanCore storage loan = loans[loanId];
        LoanTerms storage term = terms[loanId];
        require(loan.state == LoanState.Active);
        require(term.extensions < 3);
        require(term.totalRepaid >= term.loanAmount / 2);
        
        term.duration += 30 days;
        term.extensions++;
        loan.state = LoanState.Extended;
    }
    
    function defaultLoan(uint256 loanId) external {
        LoanCore storage loan = loans[loanId];
        LoanTerms storage term = terms[loanId];
        require(block.timestamp > term.startTime + term.duration);
        require(loan.state == LoanState.Active || loan.state == LoanState.Extended);
        
        uint256 fee = (term.downPayment * settings.DEFAULT_FEE()) / 1000;
        
        loan.state = LoanState.Defaulted;
        IERC721(loan.nft).transferFrom(address(this), loan.seller, loan.tokenId);
        payable(loan.seller).transfer(fee);
        payable(loan.buyer).transfer(term.totalRepaid - fee);
    }
    
    function _getTotalDue(LoanTerms memory term) internal pure returns (uint256) {
        return term.loanAmount + ((term.loanAmount * term.interestRate * (term.duration + term.extensions * 30 days)) / (365 days * 1000));
    }
    
    function _completeLoan(uint256 loanId) internal {
        LoanCore storage loan = loans[loanId];
        LoanTerms storage term = terms[loanId];
        loan.state = LoanState.Completed;
        IERC721(loan.nft).transferFrom(address(this), loan.buyer, loan.tokenId);
        payable(loan.seller).transfer(term.totalRepaid);
    }
    
    function getTotalDue(uint256 loanId) external view returns (uint256) {
        return _getTotalDue(terms[loanId]);
    }
}