"""Combine original-window evidence from the admitted macOS witness."""
def original_hit(native):
    hits=native.get('originalAXHits')
    if not isinstance(hits,dict) or hits.get('blockedByProtectedSurface') is not False:
        return False
    return (native.get('cgWindowOnScreen') is True and
            (native.get('centerHitOriginalCG') is True or native.get('originalAXHitQuorum') is True))
