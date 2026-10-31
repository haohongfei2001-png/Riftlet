on run argv
 set wantedWindow to item 1 of argv as integer
 set wantedTab to item 2 of argv as integer
 set js to read POSIX file (item 3 of argv) as «class utf8»
 with timeout of 8 seconds
  tell application "Google Chrome"
   set w to first window whose id is wantedWindow
   set t to first tab of w whose id is wantedTab
   if URL of t is not "https://chatgpt.com/" then error "TARGET_ROUTE_CHANGED_NO_ACTION"
   set URL of t to "javascript:" & js
   return "JAVASCRIPT_URL_REQUESTED_NOT_CONFIRMED"
  end tell
 end timeout
end run
