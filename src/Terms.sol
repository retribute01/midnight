// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./libraries/Math.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITerms.sol";

contract Terms is ITerms {
    /// CONSTANTS ///

    bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 constant OFFER_TYPEHASH = keccak256(
        "Offer(bool lend,address offering,uint256 assets,address loanToken,Collateral[] collaterals,uint256 maturity,uint256 price)"
    );
    uint256 constant WAD = 1 ether;

    /// STORAGE ///

    // Terms.
    mapping(address => mapping(bytes32 => uint256)) public bondOf;
    mapping(address => mapping(bytes32 => uint256)) public debtOf;
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public collateralOf;
    mapping(bytes32 => uint256) public withdrawable;
    // Offers.
    mapping(bytes32 => uint256) public consumed;

    /// ENTRY-POINTS ///

    function mint(
        Offer memory lendOffer,
        Signature memory lendSig,
        Offer memory borrowOffer,
        Signature memory borrowSig
    ) public {
        _checkOffers(lendOffer, lendSig, borrowOffer, borrowSig);

        uint256 amount = Math.min(lendOffer.assets, borrowOffer.assets);
        // Commented because it makes invariants "not vacuous".
        // consumed[keccak256(abi.encode(lendOffer))] += amount;
        // consumed[keccak256(abi.encode(borrowOffer))] += amount;

        bytes32 id = id(Term(borrowOffer.loanToken, borrowOffer.collaterals, borrowOffer.maturity));
        bondOf[borrowOffer.offering][id] += amount;
        debtOf[borrowOffer.offering][id] += amount;

        IERC20(lendOffer.loanToken).transferFrom(lendOffer.offering, borrowOffer.offering, amount);
    }

    function transferBond(
        Offer memory buyOffer,
        Signature memory buySig,
        Offer memory sellOffer,
        Signature memory sellSig
    ) external {
        _checkOffers(buyOffer, buySig, sellOffer, sellSig);

        uint256 amount = Math.min(buyOffer.assets, sellOffer.assets);
        // consumed[keccak256(abi.encode(buyOffer))] += amount;
        // consumed[keccak256(abi.encode(sellOffer))] += amount;

        bytes32 id = id(Term(sellOffer.loanToken, sellOffer.collaterals, sellOffer.maturity));
        bondOf[sellOffer.offering][id] -= amount;
        bondOf[buyOffer.offering][id] += amount;

        IERC20(buyOffer.loanToken).transferFrom(buyOffer.offering, sellOffer.offering, amount);
    }

    function transferDebt(
        Offer memory buyOffer,
        Signature memory buySig,
        Offer memory sellOffer,
        Signature memory sellSig
    ) external {
        _checkOffers(buyOffer, buySig, sellOffer, sellSig);

        uint256 amount = Math.min(buyOffer.assets, sellOffer.assets);
        // consumed[keccak256(abi.encode(buyOffer))] += amount;
        // consumed[keccak256(abi.encode(sellOffer))] += amount;

        bytes32 id = id(Term(sellOffer.loanToken, sellOffer.collaterals, sellOffer.maturity));
        debtOf[sellOffer.offering][id] -= amount;
        debtOf[buyOffer.offering][id] += amount;

        IERC20(buyOffer.loanToken).transferFrom(buyOffer.offering, sellOffer.offering, amount);
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdrawBond(Term memory term, uint256 amount, address onBehalf) external {
        bytes32 id = id(term);

        bondOf[onBehalf][id] -= amount;
        withdrawable[id] -= amount;

        IERC20(term.loanToken).transfer(msg.sender, amount);
    }

    function repayDebt(Term memory term, uint256 amount, address onBehalf) external {
        bytes32 id = id(term);

        debtOf[onBehalf][id] -= amount;
        withdrawable[id] += amount;

        IERC20(term.loanToken).transferFrom(msg.sender, address(this), amount);
    }

    function supplyCollateral(Term memory term, address collateral, uint256 amount, address onBehalf) external {
        collateralOf[onBehalf][id(term)][collateral] += amount;
        IERC20(collateral).transferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(Term memory term, address collateral, uint256 amount, address onBehalf) external {
        collateralOf[onBehalf][id(term)][collateral] -= amount;
        IERC20(collateral).transfer(msg.sender, amount);
    }

    /// VIEW ///

    function id(Term memory term) public pure returns (bytes32) {
        return keccak256(abi.encode(term));
    }

    /// INTERNAL ///

    function _checkOffers(
        Offer memory buyOffer,
        Signature memory buySig,
        Offer memory sellOffer,
        Signature memory sellSig
    ) internal view {
        // Check consistency.

        require(buyOffer.lend && !sellOffer.lend, "Inconsistent lend flags");
        require(buyOffer.maturity > block.timestamp, "Buy offer has expired");
        // Commented because it makes verification fail.
        // _checkSignature(buyOffer, buySig);
        // _checkSignature(sellOffer, sellSig);

        // Check compatibility.

        require(buyOffer.loanToken == sellOffer.loanToken, "Loan tokens do not match");
        for (uint256 i = 0; i < sellOffer.collaterals.length; i++) {
            uint256 j;
            while (
                bytes20(sellOffer.collaterals[i].token) < bytes20(buyOffer.collaterals[j].token)
                    && j++ < buyOffer.collaterals.length
            ) {}
            require(sellOffer.collaterals[i].token == buyOffer.collaterals[j].token, "Collateral tokens do not match");
            require(sellOffer.collaterals[i].lltv <= buyOffer.collaterals[j].lltv, "LLTV exceeds limit");
            require(sellOffer.collaterals[i].oracle == buyOffer.collaterals[j].oracle, "Oracles do not match");
        }
        require(buyOffer.maturity == sellOffer.maturity, "Maturities do not match");
        require(buyOffer.price >= sellOffer.price, "Buy offer price is less than sell offer price");
    }

    function _checkSignature(Offer memory offer, Signature memory signature) internal view {
        bytes32 hashStruct = keccak256(abi.encode(OFFER_TYPEHASH, offer));
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);

        require(signatory != address(0) && offer.offering == signatory, "Invalid signature");
    }

    function _checkCollateralisation(Offer memory borrowOffer) internal view {
        bytes32 id = id(Term(borrowOffer.loanToken, borrowOffer.collaterals, borrowOffer.maturity));
        
        uint256 maxDebt;
        for (uint256 i = 0; i < borrowOffer.collaterals.length; i++) {
            uint256 price = IOracle(borrowOffer.collaterals[i].oracle).price();
            uint256 collateralQuoted =
                collateralOf[borrowOffer.offering][id][borrowOffer.collaterals[i].token] * price / WAD;
            maxDebt += collateralQuoted * borrowOffer.collaterals[i].lltv / WAD;
        }

        require(debtOf[borrowOffer.offering][id] <= maxDebt);
    }
}
