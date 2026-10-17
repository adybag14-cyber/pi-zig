// Prepared Source observer entry only. Future owner must import the actual
// pinned c268 chord/src/sqlite/cloudflare.ts and supply the real Durable Object
// storage capability plus its owned SQL-table label. No capture has run.
import observe from '../../src/extensions/fixtures/chord-sqlite-cloudflare-c268-observer.mjs';
export default async function observeOriginal(originalModule,actualStorage,ownedTableLabel){
  return observe(originalModule,actualStorage,ownedTableLabel);
}
