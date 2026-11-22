"""Build the two private QA executables from the release's original-tab observer."""
import argparse
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLAIM = '''try check(QAOriginalBrowserTab.temporaryChat)
        guard let data = ProcessInfo.processInfo.environment["RIFTLET_SELECTION_CLAIM"]?.data(using: .utf8),
              var claim = try JSONSerialization.jsonObject(with: data) as? [String: String],
              ["operation","invocation","evidence","documentID","nonce"].allSatisfy({ UUID(uuidString: claim[$0] ?? "") != nil }),
              let composer = claim["composerID"], composer.range(of: "^node-[0-9]+:node-[0-9]+$", options: .regularExpression) != nil,
              ["init","state","before","after"].contains(claim["mode"]), claim["marker"] == nil else {
            throw Identity.Refusal("SCOPED_SELECTION_CLAIM_REQUIRED")
        }
        claim["marker"] = marker
        let claimData = try JSONEncoder().encode(claim)
        let script = source.replacingOccurrences(of: "CLAIM_LITERAL", with: String(decoding: claimData, as: UTF8.self))
        let reply = try Owned.request(process,"CrSu","ExJa",["----":tab,"JvSc":.init(string:script)])'''
PINNED_EDITOR = '''  const pinned = globalThis.__riftletIndependentFileInput20261104;
  const generation = (pinned?.root === document.documentElement) && pinned.witnessGeneration;
  const form = generation?.form, editor = generation?.editor;
  if (!form?.isConnected || !editor?.isConnected || !editor.isContentEditable || !form.contains(editor) ||
      !visible(editor) || !visible(form) || editor.closest('aside,nav,article,[data-message-author-role]')) return '';
'''

def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError("Original-tab QA source has changed. Review the integration against that revision.")
    return source.replace(old, new)

def build(repo, products, output):
    sources = repo / 'Tests/PreClickLease/native'
    output.mkdir(exist_ok=False, parents=True)
    swift = (sources / 'OriginalDraftObserver.swift').read_text()
    dispatch = 'let reply = try Owned.request(process,"CrSu","ExJa",["----":tab,"JvSc":.init(string:source)])'
    (output / 'SelectionNative.swift').write_text(replace_once(swift, dispatch, CLAIM))

    renderer = (sources / 'ReadOriginalDraft.swift').read_text()
    start = renderer.index('  const forms =')
    end = renderer.index('  const rawText =', start)
    renderer = renderer[:start] + PINNED_EDITOR + renderer[end:]
    resources = [
        repo / 'Tests/DerivedPreview/draft-selection.js',
        HERE / 'observe.js',
        HERE / 'selection-sampler.js',
    ]
    extra = '\n'.join(resource.read_text() for resource in resources)
    first = '  return JSON.stringify({observationState,entryID:navigation.currentEntry.id,'
    renderer = replace_once(renderer, first, extra + '\n' + first.replace('{observationState,', '{selectionProbe,observationState,'))
    (output / 'SelectionRead.swift').write_text(renderer)
    cache = str(output / 'module-cache')
    subprocess.run([
        'xcrun','clang','-fobjc-arc','-fmodules','-fmodules-cache-path='+cache,
        '-framework','Cocoa','-framework','ApplicationServices',HERE/'ax_prepare.m','-o',output/'ax_prepare',
    ], check=True)
    subprocess.run([
        'xcrun','swiftc','-parse-as-library','-D','ORIGINAL_DRAFT_OBSERVER','-module-cache-path',cache,
        '-I',products,'-I',repo/'Sources/CSQLite',sources/'identity.swift',sources/'owned.swift',sources/'press.swift',
        output/'SelectionNative.swift',output/'SelectionRead.swift',products/'RiftletAdapters.o',products/'RiftletCore.o',
        '-lsqlite3','-o',output/'selection-observer',
    ], check=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--products', required=True, type=Path, help='macOS Debug products root containing RiftletAdapters.o, RiftletCore.o and swiftmodules')
    parser.add_argument('--output', required=True, type=Path, help='fresh private build directory')
    args = parser.parse_args()
    build(args.repo.resolve(), args.products.resolve(), args.output.resolve())
