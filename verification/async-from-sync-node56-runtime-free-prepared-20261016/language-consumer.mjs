// Genuine language reference/guest control, never a production adapter.
export async function consume(input,mode,visit,reason){
 const values=[];
 for await(const value of input){
  values.push(value);
  await visit(value,values.length);
  if(mode==='break')break;
  if(mode==='return')return {kind:'return',values};
  if(mode==='throw')throw reason;
 }
 return {kind:'normal',values};
}
