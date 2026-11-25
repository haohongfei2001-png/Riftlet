# Conversation provider receiver tests

The two Chromium runs exercise the production page function against isolated synthetic drafts. They run in a disposable headless process and fulfill the entire page locally. The cross-world pin runs in an isolated renderer world, followed by the actual capture, begin, chunk, commit and observation commands in the page world.

Use Node and Playwright Core with an installed Chrome or Edge. The QA driver is development-only. An existing installation of Playwright Core can be located with Node's standard NODE_PATH.

~~~sh
node Tests/ConversationProviders/run.cjs chrome
node Tests/ConversationProviders/run.cjs edge
~~~

Each provider case checks two different images, one setter/input/change per explicit action, separate attachment IDs and START receipts, a backward selection, the original text and attachment, and zero sends or submissions. Focused cases cover invalidated document, editor and field bindings, detached and portalled pickers, label ambiguity, an unrelated file field, conflicting progress and error indicators, replacement of an old attachment, pixel mismatch and loss of the page receipt. No case exercises an authenticated provider account, a macOS application click or a native drag.

The public page survey records the origin, the kind of composer and the attachment entry visible to a fresh guest. Several sites returned sign-in screens or HTTP 403. Where a real composer was unavailable the program can recognize an explicitly service-branded editable chat in a dedicated form with a named file entry. Other forms are refused. The Claude and Mistral documentation describes their user-visible attachment commands. These sources do not establish the DOM of an authenticated session. [Claude file upload](https://support.claude.com/en/articles/8241126-upload-files-to-claude) and [Mistral files and canvas](https://docs.mistral.ai/vibe/work/web/files-and-canvas).
