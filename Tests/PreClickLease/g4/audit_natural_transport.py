"""Read the specific signed build 59 natural G4 run and its retained transport evidence."""
import argparse
import hashlib
import json
from pathlib import Path

from audit_history import require


def audit(root, directory):
    def read(name):
        return json.loads((directory/name).read_bytes())
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    docs=root/'docs/releases/1.0.8/evidence/build59'
    admitted=json.loads((docs/'g4-native-natural.json').read_bytes())
    hashes={name:sha(directory/name) for name in admitted['privateReceiptSHA256']}
    require(hashes==admitted['privateReceiptSHA256'],'Natural receipt changed')
    capture=read('capture-1.json')
    observed=read('g4-original-observed.json')
    site=read('final-page.json')
    rows=read('final-db.json')
    op,=rows['operations']
    source,=rows['assets']
    src=source['sha256']; name='riftlet-'+op['id'].lower()+'.png'
    require(capture['systemScreenshotMarker'] and capture['ownerVerified'] and src==capture['sha256']==admitted['systemScreenshotSHA256'] and
            op['startMatchesOriginal'] and op['startSignal']=='attachmentAccepted' and op['startCount']==1 and op['hasError'] is False and
            observed['acceptanceFailureVerified'] is False and not any(c['uniqueNamedCard'] for c in site['g4ErrorCards']),
            'Natural run lacks its original positive card')
    received=site['observedInputReceipts']
    require(site['counts']=={'fileInput':1,'fileChange':1,'formSubmit':0,'sendButtonClicks':0} and
            [r['event'] for r in received]==['input','change'] and len({r['bytes'] for r in received})==1 and
            all(r['sha256']==src and r['knownQAFileName'].lower()==name and r['sameInputAsOriginal'] for r in received),
            'Receiver claims do not match the source')
    timings=site['knownUploadEndpoints']
    require(timings==observed['site']['knownUploadEndpoints'] and len(timings)==2 and
            all(set(r)=={'atMS','durationMS','kind','publicPath','responseStatus'} for r in timings) and
            [(r['kind'],r['publicPath'],r['responseStatus']) for r in timings]==[
                ('fetch','/backend-api/files',200),('fetch','/backend-api/files/process_upload_stream',None)
            ], 'Unexpected retained timing details')
    require(read('g4-no-injection.json')['requestedNetworkChanges']==0,'The original run applied a fault')
    supplied=['Tests/PreClickLease/g4/'+n for n in ['README.md','card-observer.js','verify_recovery.py','test_recovery.py']]
    legacy='engineering/evidence/2026-10-27-real-mac-round2/'
    supplied += [legacy+n for n in ['network-fault.template.js','post100-network-receipt.json','mid-network-receipt.json']]
    historical={}
    for short in ['post100','mid']:
        old=json.loads((root/(legacy+short+'-network-receipt.json')).read_bytes())
        ev=old['events']; life=[e for e in ev if e['event']=='native_bytes_request_started']
        controls=[e for e in ev if e['event']=='native_abort_requested']
        require(old['state']=='STOPPED' and old['requestsInitiatedByBridge']==0 and old['pendingRequests']==0 and ev[-1]['originalsRestored'],
                'Historical lab bridge restoration missing')
        details={'inputBytes':next(e['byteCount'] for e in ev if e['event']=='own_input_observed'),
                 'creationRequests':old['createCount'],'exactRequestBodyHashMatched':any(e['event']=='own_bytes_hash' and e['matched'] for e in ev),
                 'uniqueCreationURLWasObservedInMemory':any(e['event']=='own_creation_linkage' and e['uniqueURL'] for e in ev),
                 'storedTransferURLOrURLHash':False,'nativeByteRequests':len(life),'abortRequests':len(controls),'requestTransport':life[0]['transport'] if life else None}
        require((short=='post100')==(len(life)==len(controls)==1 and details['exactRequestBodyHashMatched']),'Historical fault classification changed')
        historical[short]=details
    return {'analysisScope':'Prior real signed build 59 natural transfer only','dmgSHA256':admitted['dmgSHA256'],'browser':admitted['browser'],
            'authenticatedOriginalTemporaryChat':True,'inputPNGBytes':received[0]['bytes'],'originalFileSHA256':src,
            'timingRowsFromSameOriginPerformanceEntries':timings,
            'uploadRequest':{'completeURLOrHash':'NOT_OBSERVED','method':'NOT_OBSERVED','requestBodyRepresentation':'NOT_OBSERVED','fullPayloadMatchedToOriginalPNG':'NOT_OBSERVED','liveSingleRequestCancellationHandle':'NOT_OBSERVED'},
            'site':{'fileInputs':1,'fileChanges':1,'originalAttachmentAcceptedSTARTs':1,'explicitOriginalErrorCards':0,'submits':0,'sends':0},
            'controlledFault':'NOT_RUN','failureRecovery':'NOT_RUN','beforeAndAfterRecoverySQLite':'NOT_RUN',
            'historicalOtherOperations':historical,'independentlyReviewedSources':{n:sha(root/n) for n in supplied},
            'checkedRawSHA256':hashes}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run_directory',type=Path)
    args=parser.parse_args()
    print(json.dumps(audit(Path(__file__).resolve().parents[3],args.run_directory),sort_keys=True,indent=2))
