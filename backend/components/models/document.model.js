export const defaultDocumentPrice = 100;
export const defaultProcessingFee = 0;

const documentPrices = Object.freeze({
  'f-137 (sh)': 400,
  'f-137 (gs/jh)': 250,
  tor: 600,
  'transcript of records': 600,
  'transcript of records (tor)': 600,
  gwa: 250,
  'general weighted average (gwa)': 250,
  'gmc/esc': 200,
  'good moral character/esc (gmc/esc)': 200,
  'certificate of good moral': 200,
  'card (re-print)': 200,
  moi: 250,
  'moi (memorandum of inclusion)': 250,
  'student verification': 250,
  'request form (lost)': 200,
  ctc: 200,
  'certified true copy (ctc)': 200,
  'ctc of certificate of matriculation': 200,
  'ctc of diploma': 200,
  'ctc of curriculum': 200,
  'diploma (2nd copy)': 300,
  'application for grad': 200,
  'application for graduation': 200,
  'certificate of candidacy for graduation': 200,
  prospectus: 200,
  'cert. of grades': 250,
  'certificate of grades': 250,
  'grade certification': 250,
  'transfer credential': 300,
  'cert. of enrollment': 250,
  'certificate of enrollment': 250,
  clearance: 200,
  'certificate of units earned': 200,
  'certificate of assessment': 200,
  'certificate of registration': 200,
  others: 0,
});

export function getDocumentPrice(docName) {
  const key = String(docName || '').trim().toLowerCase();
  if (!key) return defaultDocumentPrice;
  if (documentPrices[key] != null) return documentPrices[key];
  if (key.includes('ctc')) return 200;
  return defaultDocumentPrice;
}
