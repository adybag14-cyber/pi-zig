// Authored cases for separate owned Node processes; not expected outputs.
export const policies=[
 {id:'pipe-default',env:{},argv:[]},
 {id:'force-false',env:{FORCE_COLOR:'false'},argv:[]},
 {id:'force-true',env:{FORCE_COLOR:'true'},argv:[]},
 {id:'force-empty',env:{FORCE_COLOR:''},argv:[]},
 ...['0','1','2','3','9','000','2x'].map(value=>({id:'force-'+value,env:{FORCE_COLOR:value},argv:[]})),
 {id:'flag-none',env:{},argv:['--no-color']},
 {id:'flag-full',env:{},argv:['--color=full']},
 {id:'flag-256',env:{},argv:['--color=256']},
 {id:'env-overrides-disable-flag',env:{FORCE_COLOR:'3'},argv:['--no-color']},
 {id:'zero-overrides-full-flag',env:{FORCE_COLOR:'0'},argv:['--color=full']},
 {id:'terminator',env:{},argv:['--','--color=full']},
 {id:'no-color-presence',env:{NO_COLOR:'1'},argv:[]},
 {id:'forced-numeric-no-color-presence',env:{FORCE_COLOR:'2',NO_COLOR:'1'},argv:[]},
 {id:'azure-pipe',env:{TF_BUILD:'1',AGENT_NAME:'owned-fixture'},argv:[]},
 {id:'github-with-boolean-force',env:{FORCE_COLOR:'true',CI:'1',GITHUB_ACTIONS:'1'},argv:[]},
 {id:'dumb-with-boolean-force',env:{FORCE_COLOR:'true',TERM:'dumb'},argv:[]},
];