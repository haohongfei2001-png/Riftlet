# Production preservation and recovery

[Comparison and private evidence hashes](result.json), [logical storage accounting](logical-storage-accounting.json).

The formal App was normally exited before the fresh offline backup. Both cooperative application/database locks were acquired; read-only verification operates on disposable copies rather than a live production SQLite connection. After the isolated complete-App GUI run, a second offline capture had identical204 file entries/content and all typed database rows. Both databases were healthy, including96 assets/media,44 operations,18 START and the same three UNKNOWN sequences.

A separate restore drill used the first snapshot’s external manifest pin and a new private destination. It verified content and database health without launching the restored data or replacing production. The formal App then restarted normally at the exact original installed binary. Old Beta2 rollback App, installer and prior upgrade backups remain preserved.

The logical snapshot size is153,171,996bytes (about146.08MiB), including152,190,127bytes of private media. This is not filesystem allocation, current live usage, system-original screenshot size, or the size of all backup copies. No deletion policy or cleanup action was introduced. Original screenshots, private copies, journal/history and UNKNOWN remain separate concepts; hiding/archiving/removing from the visible queue does not free their media storage.

The preference comparison uses the previous Beta3-delivery export; mode-bit comparison uses the previous upgrade metadata baseline. Their exact scope is retained instead of describing either as a fresh sprint-start capture. Original overbroad mode wording is retained privately with its correction. Raw database rows, filenames and production content stay private.
