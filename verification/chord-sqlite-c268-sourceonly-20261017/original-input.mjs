// Genuine reference input, never executed. Uses original public modules only.
import * as portable from '@earendil-works/chord/sqlite';
import * as node from '@earendil-works/chord/sqlite/node';
import * as durableNode from '@earendil-works/pi-durable/storage/sqlite/node';
export async function collect() {
  const rows = [];
  rows.push({case:'exports',portable:Object.keys(portable),node:Object.keys(node),identicalClass:node.NodeSqliteDatabase===durableNode.NodeSqliteDatabase,identicalOpen:node.openNodeSqliteDatabase===durableNode.openNodeSqliteDatabase});
  for (const prefix of ['x','_','A_09','a\n','','1x','a-b','é','sqlite_x','SQLITE_']) {
    try { rows.push({case:'prefix',prefix,result:portable.validateSqliteSchemaPrefix(prefix)}); }
    catch (error) { rows.push({case:'prefix',prefix,error:{name:error.name,message:error.message}}); }
  }
  const database = await node.openNodeSqliteDatabase(':memory:');
  try {
    const migrations=[{version:1,statements:['CREATE TABLE values_table(id INTEGER PRIMARY KEY,value TEXT)','INSERT INTO values_table VALUES(1,\'one\')']},{version:2,statements:['INSERT INTO values_table VALUES(2,\'two\')']}];
    await portable.applySqliteMigrations(database,migrations,{table:'metadata'});
    rows.push({case:'apply',data:await database.all('SELECT * FROM values_table ORDER BY id'),metadata:await database.get('SELECT version FROM metadata')});
    await portable.applySqliteMigrations(database,migrations,{table:'metadata'});
    rows.push({case:'idempotent',data:await database.all('SELECT * FROM values_table ORDER BY id')});
    for (const [name,history] of [['gap',[{version:2,statements:[]}]],['newer',migrations.slice(0,1)],['rollback',[...migrations,{version:3,statements:['INSERT INTO values_table VALUES(3,\'three\')','INVALID SQL']}]]]) {
      try { await portable.applySqliteMigrations(database,history,{table:'metadata'});rows.push({case:name,unexpected:true}); }
      catch(error) { rows.push({case:name,error:{name:error.name,message:error.message},data:await database.all('SELECT * FROM values_table ORDER BY id'),metadata:await database.get('SELECT version FROM metadata')}); }
    }
    const trace=[],wrapped=new Proxy(migrations,{get(target,key,receiver){trace.push(String(key));return Reflect.get(target,key,receiver)}});
    await portable.applySqliteMigrations(database,wrapped,{get table(){trace.push('table');return 'metadata'}});
    rows.push({case:'live-getters',trace});
    let escaped;await database.transaction(async transaction=>{escaped=transaction;await transaction.get('SELECT 1')});
    try { await escaped.get('SELECT 1'); } catch(error) { rows.push({case:'expired',error:{name:error.name,message:error.message}}); }
  } finally { await database.close(); }
  return {authority:'c268154ca1171c2f9eefe75d3d7372a68aada2d5',rows};
}
