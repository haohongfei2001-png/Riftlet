export function publishedDocuments(snapshot) {
  return new Set((snapshot?.events || []).filter(e => e.event === 'publishAck' && typeof e.documentID === 'string')
    .map(e => e.documentID));
}
export function hasNewDocumentPublication(snapshot, originalDocuments) {
  return [...publishedDocuments(snapshot)].some(id => !originalDocuments.has(id));
}
