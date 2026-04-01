// SPDX-License-Identifier: GPL-2.0-or-later

using Midnight as midnight;

methods {
    function nonce(address) external returns (uint256) envfree;
    function MIDNIGHT() external returns (address) envfree;

    function midnight.isAuthorized(address, address) external returns (bool) envfree;

    function signer(bytes32, EcrecoverRatifier.Signature memory) internal returns (address) => signerGhost();
}

persistent ghost address lastSigner;

function signerGhost() returns address {
    address s;
    require s != 0;
    lastSigner = s;
    return s;
}

/// onRatify only succeeds when signer == maker or signer is authorized by maker.
rule onRatifyRequiresMakerOrAuthorized(env e, EcrecoverRatifier.Offer offer, bytes32 root, bytes data) {
    onRatify(e, offer, root, data);
    assert lastSigner == offer.maker || midnight.isAuthorized(offer.maker, lastSigner);
}

/// setIsAuthorizedWithSig requires caller auth, valid signer, increments nonce, and doesn't change other nonces.
rule setIsAuthorizedWithSigEffects(env e, address authorizer, address authorized, bool isAuth, EcrecoverRatifier.Signature signature, address other) {
    require other != authorizer;
    uint256 nonceBefore = nonce(authorizer);
    uint256 otherNonceBefore = nonce(other);
    bool callerWasAuthorized = midnight.isAuthorized(authorizer, e.msg.sender);

    setIsAuthorizedWithSig(e, authorizer, authorized, isAuth, signature);

    assert e.msg.sender == authorizer || callerWasAuthorized;
    assert lastSigner == authorizer;
    assert nonce(authorizer) == nonceBefore + 1;
    assert nonce(other) == otherNonceBefore;
}
