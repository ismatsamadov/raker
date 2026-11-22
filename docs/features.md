# Mac cleaner feature research

Researched November 22, 2026 for a native Mac desktop app aimed at everyday users.

**The first release should help someone running out of space find files they recognize and decide which ones to remove.** Ship a size-ranked browser, Downloads and installer review, exact duplicate detection, previews, and a recoverable move to Trash. Show how much storage actually becomes available. For a second release, answer “What grew since last time?” so someone whose disk fills up again can trace the cause. [OmniDiskSweeper] · [Gemini 2] · [DiskFox]

The inventory groups 51 capabilities from 21 third-party Mac desktop products and compares them with Apple’s built-in tools. Each row links to examples from product sites, support guides, or maintainers’ repositories. This is a representative survey of documented features. Space savings and performance were not independently measured.

## What Mac users already have

| Built-in tool | What it already does | Implication for a new cleaner |
| --- | --- | --- |
| System Settings → General → Storage | Shows available space and usage by category. Users can review documents and device backups, store files in iCloud, remove watched media, and opt to empty Trash after 30 days. macOS also clears some caches and logs when space is needed. | A second storage bar offers little value on its own. Show the actual folders behind a total, explain why each item appeared, and give the user a reviewable action. [Apple storage] · [Apple optimization] |
| Finder and iCloud Drive | Finder can put a trashed file back before Trash is emptied. For an iCloud Drive file, Remove Download releases the local copy. Deleting the synced file propagates to other devices. | Label actions by where they take effect. A cloud-only file can be large online and occupy very little local space. [Finder Trash] · [iCloud Drive] |
| Photos | The Duplicates collection lets people merge duplicate photos and videos. Removed copies remain in Recently Deleted for 30 days. | Start with ordinary files in selected folders. A later photo feature can earn its place by comparing near-matches or working across libraries. [Apple Photos] · [PhotoSweeper] |
| Time Machine and APFS | macOS counts local snapshot space as available and reclaims it when needed. APFS copies can share underlying disk blocks. | Report the size of selected files, the amount moved to Trash, and the observed change in available space separately. Adding up file sizes can overstate the gain. [Time Machine] · [Apple File System] |

## Feature inventory

### Finding what uses space

| Capability | What the user can do | Documented examples |
| --- | --- | --- |
| Guided scan | Run one scan across several categories and open the findings for review. | [CleanMyMac tools] · [Cleaner One Pro] · [BuhoCleaner] |
| Largest files and folders | Browse largest-first, drill into a folder, and open an item. A ranked list works even when one directory contains thousands of small files. | [OmniDiskSweeper] · [MacCleaner Pro] |
| Visual disk map | Explore a treemap or radial map where area represents size. Zoom into the directory responsible for a large block. | [GrandPerspective] · [DaisyDisk map] |
| Scope and volume selection | Scan a chosen folder, internal disk, removable drive, or mounted network share. Some tools can also inspect connected cloud accounts. | [DaisyDisk] · [Duplicate File Finder FAQ] |
| Filters and hidden files | Find items by name, path, type, size, or age. Inspect hidden content or treat an app package as a single item. | [GrandPerspective] · [MacCleaner Pro] |
| Explain “System Data” and gaps | Identify recognizable contributors such as device backups, development tools, or VM images. Show inaccessible or unaccounted space explicitly. | [DiskFox] · [DaisyDisk] |
| Historical growth and alerts | Compare dated scans, see which category grew, and receive a notification if the space fills again. A saved scan can also be reloaded or exported as text or an image. | [DiskFox] · [GrandPerspective] |
| Menu bar storage monitor | Check available space without opening a full scan and receive a configurable low-space notification. | [CleanMyMac disk monitor] · [BuhoCleaner] |

### Cleaning everyday clutter

| Capability | What the user can review or remove | Documented examples |
| --- | --- | --- |
| Caches, logs, and temporary files | Review generated files by app or system category. Show the owner and explain which data will rebuild. | [MacKeeper] · [MacCleaner Pro] · [CleanMyMac editions] |
| Old downloads and installers | Find forgotten browser or chat downloads, disk images, installer packages, and compressed archives. Keep the decision with the user because an archive can be their only copy. | [CleanMyMac editions] · [MacCleaner Pro] · [Washing Machine] |
| Large and old personal files | Filter bulky or long-untouched documents, videos, music, and recordings by size and date. | [BuhoCleaner] · [MacCleaner Pro] |
| Screenshots and downloaded media | Review accumulated screenshots as a group. Identify downloaded films, TV, or podcasts that can be removed from the device. | [MacKeeper] · [Apple file review] |
| Mail and Messages attachments | Identify locally stored Mail attachment copies or storage used by Messages attachments. The source app and account determine the available action. | [CleanMyMac tools] · [DiskFox] |
| Old iPhone and iPad data | Identify local device backups and firmware, with enough context to recognize a backup worth keeping. | [Apple storage] · [CleanMyMac editions] |
| Trash across locations | Inspect the startup disk’s Trash, external-volume Trash, or Mail Trash. Some products also automate emptying Trash by age or size. | [CleanMyMac editions] · [Hazel] · [CCleaner for Mac] |
| Document versions and account remnants | Surface old document revisions, broken preferences, and files left by deleted user accounts for individual review. Versions and former home folders can contain irreplaceable data. | [CleanMyMac editions] |
| Cloud storage and local downloads | Inspect remote quota, find large cloud files, remove downloaded copies, or explicitly delete synced files from the account. Documented providers include iCloud Drive, Google Drive, OneDrive, Dropbox, and, in DaisyDisk, Box. | [CleanMyMac cloud] · [DaisyDisk] |
| Email inbox cleanup | Connect a mailbox, group newsletters or promotions, then archive, delete, or unsubscribe in batches. This changes the mailbox itself. | [CleanMyMac email] |

### Duplicates, photos, and file organization

| Capability | What the user can do | Documented examples |
| --- | --- | --- |
| Exact duplicate files | Find identical content under different names or in different folders. Review copies as a group, with their paths visible. | [MacKeeper] · [DiskFox] · [Washing Machine] |
| Choose which copy survives | Prefer a folder, the oldest or newest file, or a manually locked original. Apply that preference across groups and preview the selection. | [Washing Machine] · [Avast Cleanup] · [PhotoSweeper] |
| Compare and merge folders | Detect duplicate directories, compare contents, and merge overlapping folders while retaining unique files. | [MacCleaner Pro] |
| Near-duplicate and poor-quality photos | Compare similar shots side by side, adjust similarity, group a burst by time, or flag blurry and poorly lit photos for human review. | [PhotoSweeper] · [Avast Cleanup] |
| Media-library support | Work with Apple Photos, Lightroom Classic, or Capture One. Inspect RAW/HEIC files, metadata, and edited versions. Gemini also advertises duplicate music detection. | [PhotoSweeper] · [Gemini 2] |
| New duplicate alerts | Monitor for newly created copies and prompt the user while they still know which one to keep. | [Gemini 2] |
| Folder rules and filing | Watch a folder such as Downloads. Move, rename, tag, or archive matches by type, age, or name. Other tools organize the Desktop, Dock, and Finder Smart Folders. | [Hazel] · [Washing Machine] |

### Applications, browsers, and privacy

| Capability | What the user can do | Documented examples |
| --- | --- | --- |
| App inventory and uninstall | Find large or rarely opened apps. Drop an app onto an uninstaller, review its associated files, and remove the selection. Some tools support batch removal. | [AppCleaner] · [Avast Cleanup] · [CleanMyMac app manager] |
| Leftovers and app reset | Look for files left by previously removed apps. Reset an installed app’s settings as a separate action. Some tools detect when an app is moved to Finder Trash and offer to handle support files. | [MacCleaner Pro] · [Hazel] · [Pearcleaner] |
| Startup and background items | See which apps and helpers start at login, review their owners, and manage unwanted items. | [Cleaner One Pro] · [Avast Cleanup] · [CleanMyMac editions] |
| Extensions, plug-ins, and services | Inventory browser extensions, old widgets, preference panes, plug-ins, or installed services. | [MacKeeper] · [MacCleaner Pro] · [Pearcleaner] |
| App updates | Identify available versions, read changes, skip selected updates, and apply supported updates. The available actions vary by updater and distribution channel. | [MacKeeper] · [CleanMyMac editions] |
| Browser privacy cleanup | Choose a browser and the data to clear, such as cookies and browsing history. Schedule a cleanup or preserve cookies for sites where the user wants to stay signed in. | [Avast Cleanup] · [CCleaner for Mac] |
| Other privacy traces and permissions | Review recent-item lists, remembered Wi-Fi networks, and app permissions. Availability varies by edition. | [CleanMyMac editions] |
| Browser organization | Manage resource-consuming Chrome tabs. CCleaner for Mac Professional also lists browser bookmark import. | [CleanMyMac tools] · [CCleaner for Mac] |

### Developer and specialist tools

| Capability | What the user can inspect or manage | Documented examples |
| --- | --- | --- |
| Xcode storage | Break out DerivedData, package caches, simulator runtimes, device support, and distribution archives. An archive can hold the symbols needed to diagnose a shipped build. | [DevCleaner for Xcode] · [DevCleaner] |
| Package managers and build tools | Identify Homebrew downloads, npm/Yarn/pnpm caches, Python wheels, Gradle caches, and Go build output. Group findings by tool so the developer can judge the cost of a rebuild or download. | [DevCleaner] |
| Containers, emulators, and VMs | Inspect Docker build cache, dangling images, stopped containers, Android emulators, and VM disk images. Show which tool owns each item. | [DevCleaner] · [DiskFox] |
| AI tool storage | Distinguish caches and logs from downloaded model weights, conversations, and settings. Model weights may take substantial time to download again. | [DevCleaner] · [CleanMyMac tools] |
| Package and app-bundle management | Inspect installed packages and Homebrew items, export app bundles or file lists, and remove unused translations or architecture slices. Bundle modification deserves separate compatibility testing. | [Pearcleaner] · [CleanMyMac editions] |
| Advanced maintenance | Rebuild Spotlight or Mail indexes, flush DNS cache, run maintenance tasks, verify system-file structure, or adjust Finder and Dock settings. | [OnyX] · [MacCleaner Pro] · [CleanMyMac editions] |
| Purgeable space and snapshots | Inspect or request removal of purgeable data and local snapshots. Snapshot deletion gives up a local restore point, and Apple already manages retention. | [DaisyDisk] · [CleanMyMac editions] · [Time Machine] |
| System and hardware monitoring | View CPU, RAM, network, temperature, or fan activity. Some products add battery cycles, drive-health diagnostics, disk benchmarks, and SSD TRIM controls. | [BuhoCleaner] · [Sensei] |
| Memory management | Show processes using substantial memory, quit a chosen process, or offer a RAM-cleaning button. For diagnosis, Apple’s Activity Monitor explains memory pressure and the role of cached files. | [MacKeeper] · [Apple memory] |
| Security and privacy bundles | Some suites add malware and adware detection, quarantine, app vulnerability checks, ad or tracker blocking, VPN, and breach alerts. These address separate needs from reclaiming local storage. | [MacKeeper] · [Cleaner One Pro] |
| File shredding | Some cleaners advertise permanent file shredding. Apple’s Disk Utility omits secure-erase options on SSDs. A general promise of unrecoverable per-file deletion on modern Macs would need independent evidence. | [Cleaner One Pro] · [Disk Utility] |
| Physical screen cleaning | Temporarily lock keyboard input so the user can wipe the display. | [CleanMyMac tools] |

### Controls that make a cleaner usable

| Capability | What the user experiences | Documented examples |
| --- | --- | --- |
| Preview and stage | Press Space for Quick Look, reveal an item in Finder, or add items to a review list before committing. | [GrandPerspective] · [DaisyDisk collector] |
| Exclusions and protected originals | Persist ignored paths or apps, exclude a folder from scans, and lock reference photos during comparisons. | [CleanMyMac ignore lists] · [GrandPerspective] · [PhotoSweeper] |
| Recovery choices | Move selections to Trash, restore them while available, or move duplicates to a chosen folder for safekeeping. | [Gemini 2] · [Duplicate File Finder FAQ] |
| Cleanup history | Record what was approved, where it went, and how available space changed. Compare a later scan to see if the same category grew back. | [DiskFox] |
| Scheduling and integrations | Set scan reminders, schedule specific browser cleanup rules, or invoke actions through Finder, Shortcuts, or a command-line interface. | [DevCleaner for Xcode] · [Avast Cleanup] · [Hazel] · [Pearcleaner] |
| Local processing and permissions | Scan metadata locally for space analysis, read content locally when checking duplicates, and request additional access when a selected task needs it. | [DaisyDisk] · [DiskFox] |

## Recommended release scope

These are product decisions for a general-purpose Mac cleaner. The inventory above records what competitors offer.

| Priority | Build | Why it earns that position |
| --- | --- | --- |
| **First release** | User-selected local folders, largest-first browsing, old downloads and installers, exact duplicates, Quick Look, Reveal in Finder, saved exclusions, and move to Trash with a cleanup history. | A user can finish a complete cleanup and verify every choice. The same review screen serves large files, old installers, and duplicate groups. |
| **First follow-up** | Compare saved scans to answer “What grew?”, add optional low-space alerts, then add reviewed cleanup of known app caches and logs. | Growth history explains recurring storage loss. App-specific rules can explain what each cache contains and what happens when it rebuilds. |
| **Next expansion** | Add app uninstall with leftover review, external-drive cleanup, and a visual disk map. | These extend the same storage workflow. Uninstall needs reliable attribution of support files, and removable disks need volume-specific recovery handling. |
| **Audience-specific expansion** | Choose developer cleanup, photo review, or cloud storage management according to which users return. | Each requires different expertise. A developer may need an old build archive, a photographer may want both edits of a picture, and a cloud user may just want a local download removed. |
| **Separate product decision** | Evaluate antivirus, VPN, hardware tuning, forced RAM cleanup, snapshot deletion, or shredding only if the product takes on that specific job. | Each needs its own evidence of effectiveness. None is required to find a large file and recover local storage. |

### What “ready to ship” means for the first release

- **The user can start with Downloads.** Show scan progress, allow cancellation, and name any skipped locations. Request expanded access at the point of need. The Mac App Store requires App Sandbox, and CleanMyMac documents edition-specific limits on system logs, caches, and backups. Decide the distribution channel before committing to whole-disk cleanup. [App Sandbox] · [CleanMyMac editions]
- **Every deletion is reviewable.** Show the full path, size, modification date, reason for inclusion, and destination. Leave personal files unselected. For duplicate groups, verify content locally, require at least one retained copy, and recheck changed files before moving anything. [DiskFox] · [Washing Machine] · [PhotoSweeper]
- **A synced file gets a different action.** Limit the first release’s cleanup action to ordinary local files. For recognized synced locations, explain the effect and direct users to the provider’s local-storage control. In iCloud Drive, “Remove Download” keeps the remote original. [iCloud Drive] · [CleanMyMac cloud]
- **The result can be checked.** A receipt should give separate totals for moved, skipped, and failed items. Offer recovery for files still in Trash. Show the observed available-space change after emptying Trash and refreshing the volume. Shared blocks, snapshots, and unrelated disk activity can affect that measurement. [Finder Trash] · [Apple File System] · [Time Machine] · [DiskFox]

## Coverage and edition notes

| Product group | Sources surveyed |
| --- | --- |
| Eight cleanup suites | [CleanMyMac editions], [MacCleaner Pro], [CCleaner for Mac], [Avast Cleanup], [Cleaner One Pro], [BuhoCleaner], [MacKeeper], [Washing Machine] |
| Four storage analyzers | [DaisyDisk], [GrandPerspective], [OmniDiskSweeper], [DiskFox] |
| Four app and media specialists | [AppCleaner], [Pearcleaner], [Gemini 2], [PhotoSweeper] |
| Five developer, maintenance, and automation tools | [DevCleaner for Xcode], [DevCleaner], [OnyX], [Hazel], [Sensei] |

CCleaner’s Mac comparison assigns automatic browser cleaning, automatic Trash emptying, and photo analysis to Professional. Avast’s combined manual has separate Mac, Windows, and Android sections. Only its Mac section informs this inventory. Pearcleaner’s maintainer marks active development as on hold. DevCleaner for Xcode by One Minute Games and the multi-toolchain app at devcleaner.app are separate products. [CCleaner for Mac] · [Avast Cleanup] · [Pearcleaner] · [DevCleaner for Xcode] · [DevCleaner]

[Apple storage]: https://support.apple.com/guide/mac-help/change-storage-settings-mchl3d437fbc/mac
[Apple optimization]: https://support.apple.com/en-is/guide/mac-help/sysp4ee93ca4/mac
[Apple file review]: https://support.apple.com/guide/mac-help/find-and-delete-files-on-your-mac-syspf5a64aa6/27/mac/27
[Finder Trash]: https://support.apple.com/guide/mac-help/delete-files-and-folders-on-mac-mchlp1093/mac
[iCloud Drive]: https://support.apple.com/en-euro/109344
[Apple Photos]: https://support.apple.com/en-ie/guide/photos/pht5a3157c1d/mac
[Time Machine]: https://support.apple.com/en-gb/102154
[Apple File System]: https://developer.apple.com/documentation/foundation/about-apple-file-system
[App Sandbox]: https://developer.apple.com/documentation/security/app-sandbox
[Apple memory]: https://support.apple.com/en-au/guide/activity-monitor/-actmntr1004/mac
[Disk Utility]: https://support.apple.com/en-al/guide/disk-utility/dsku365552c7/mac
[CleanMyMac editions]: https://macpaw.com/support/cleanmymac/knowledgebase/missing-features
[CleanMyMac tools]: https://macpaw.com/support/cleanmymac/knowledgebase/my-tools
[CleanMyMac cloud]: https://macpaw.com/support/cleanmymac/knowledgebase/cloud-cleanup
[CleanMyMac email]: https://macpaw.com/support/cleanmymac/knowledgebase/email-cleanup-get-started
[CleanMyMac disk monitor]: https://macpaw.com/support/cleanmymac/knowledgebase/available-disk-space
[CleanMyMac ignore lists]: https://macpaw.com/support/cleanmymac/knowledgebase/ignore-lists
[CleanMyMac app manager]: https://macpaw.com/app-cleaner
[MacCleaner Pro]: https://nektony.com/mac-cleaner-pro
[Duplicate File Finder FAQ]: https://nektony.com/help/duplicate-file-finder/faq
[CCleaner for Mac]: https://www.ccleaner.com/ccleaner-mac/download
[Avast Cleanup]: https://support.avast.com/en-en/article/139/
[Cleaner One Pro]: https://cleanerone.trendmicro.com/cleaner-one-pro-for-mac/
[BuhoCleaner]: https://www.drbuho.com/buhocleaner
[MacKeeper]: https://mackeeper.com/product/
[Washing Machine]: https://support.intego.com/hc/en-us/articles/223398527-Washing-Machine-X9-User-Manual
[DaisyDisk]: https://daisydiskapp.com/specs/
[DaisyDisk map]: https://daisydiskapp.com/
[DaisyDisk collector]: https://daisydiskapp.com/guide/4/en/DeletingFiles/
[GrandPerspective]: https://grandperspectiv.sourceforge.net/
[OmniDiskSweeper]: https://www.omnigroup.com/more
[DiskFox]: https://diskfox.app/
[Gemini 2]: https://macpaw.com/gemini
[PhotoSweeper]: https://overmacs.com/
[AppCleaner]: https://freemacsoft.net/appcleaner/
[Pearcleaner]: https://github.com/alienator88/Pearcleaner
[DevCleaner]: https://devcleaner.app/
[DevCleaner for Xcode]: https://github.com/vashpan/xcode-dev-cleaner/blob/master/README.md
[OnyX]: https://titanium-software.fr/en/onyx.html
[Hazel]: https://www.noodlesoft.com/
[Sensei]: https://cindori.com/sensei
