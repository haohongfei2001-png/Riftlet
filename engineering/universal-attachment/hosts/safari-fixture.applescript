-- Compiled into a disposable runner's sender. The caller first verifies an
-- exclusive Safari process and pre-existing Automation permission without a prompt.
on exercise(fixtureURL)
using terms from application "/Applications/Safari.app"
    with timeout of 6 seconds
        tell application "/Applications/Safari.app"
            make new document with properties {URL:fixtureURL}
            set w to front window
            set wid to id of w
        end tell
        set firstDoc to my documentToken(w, fixtureURL)
        if firstDoc starts with "javascript-unavailable:" then return firstDoc
        tell application "/Applications/Safari.app"
            set firstIndex to index of current tab of w
            set extraTab to make new tab at end of tabs of w with properties {URL:fixtureURL}
            set current tab of w to extraTab
        end tell
        set secondDoc to my documentToken(w, fixtureURL)
        if secondDoc starts with "javascript-unavailable:" then return secondDoc
        if firstDoc is secondDoc then return "unproven-distinct-documents"
        tell application "/Applications/Safari.app"
            set secondIndex to index of current tab of w
            if secondIndex is firstIndex then return "unproven-distinct-tabs"
            set current tab of w to tab firstIndex of w
        end tell
        if (my documentToken(w, fixtureURL)) is not firstDoc then return "original-tab-unverified"
        tell application "/Applications/Safari.app"
            set current tab of w to tab secondIndex of w
            -- Only close the tab just created by this script, after validating
            -- both documents. This shifts the remaining sibling's native index.
            close tab firstIndex of w
            set shiftedIndex to index of current tab of w
            if shiftedIndex is secondIndex then return "tab-index-shift-unverified"
        end tell
        if (my documentToken(w, fixtureURL)) is not secondDoc then return "shifted-tab-unverified"
        tell application "/Applications/Safari.app"
            make new document with properties {URL:fixtureURL}
            set secondWindow to front window
            if id of secondWindow is wid then return "distinct-window-unverified"
        end tell
        set otherDoc to my documentToken(secondWindow, fixtureURL)
        if otherDoc starts with "javascript-unavailable:" then return otherDoc
        if otherDoc is in {firstDoc, secondDoc} then return "distinct-window-document-unverified"
        return "verified-neutral-documents"
    end timeout
end using terms from
end exercise

on documentToken(w, fixtureURL)
using terms from application "/Applications/Safari.app"
    repeat 30 times
        tell application "/Applications/Safari.app"
            if URL of current tab of w is fixtureURL then
                try
                    -- The URL is compared inside the target again before reading
                    -- the fixture-only attribute. No personal page content is read.
                    set marker to do JavaScript ("location.href === '" & fixtureURL & "' ? document.documentElement.getAttribute('data-neutral-token') : ''") in current tab of w
                on error errorText number errorCode
                    ignoring case
                        if errorText contains "JavaScript" and (errorText contains "disabled" or errorText contains "turned off" or errorText contains "not allowed" or errorText contains "allow JavaScript from Apple Events") then return "javascript-unavailable:" & (errorCode as text)
                    end ignoring
                    error "fixture-event-error" number errorCode
                end try
                if class of marker is text and length of marker is 32 then return marker
            end if
        end tell
        delay 0.1
    end repeat
    error "fixture-load-timeout" number -1712
end using terms from
end documentToken
