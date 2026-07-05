// Preuve socket RÉELLE (serveur en marche, vrais frames) de la confidentialité :
// 2 joueurs + 1 spectateur en clients socket.io bruts, partie avec bots. On attend
// un tour humain, ce joueur pioche (game:draw_card), et on inspecte le PAYLOAD reçu :
// le pilocheur reçoit sa carte, l'adversaire ET le spectateur reçoivent {hidden}.
// Complète les tests unitaires statePrivacy.test.ts (chemin broadcast réel).
// Prérequis : émulateurs + serveur (npm run dev:emulators).
import { createRequire } from 'module';
const require = createRequire(new URL('../dutch-server/package.json', import.meta.url));
const { io } = require('socket.io-client');
const SERVER='http://127.0.0.1:3000', AUTH='http://127.0.0.1:9099', PROJ='dutch-game-1dd01';
const log=(...a)=>console.log(...a);
const wait=ms=>new Promise(r=>setTimeout(r,ms));

async function tokenFor(tag){
  const s=Date.now().toString().slice(-7)+Math.floor(Math.random()*900);
  const email=`pl${tag}${s}@example.com`;
  const reg=await (await fetch(`${SERVER}/api/auth/register-password`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:`pl${tag}${s}`,displayName:`PL${tag}${s}`,email,password:'MotDePasse123'})})).json();
  if(!reg.customToken) throw new Error('register '+tag+': '+JSON.stringify(reg));
  const ex=await (await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:reg.customToken,returnSecureToken:true})})).json();
  return ex.idToken;
}
function connect(idToken){
  return new Promise((res,rej)=>{
    const sock=io(SERVER,{auth:{token:idToken},transports:['websocket'],reconnection:false});
    sock._states=[]; sock._full=[];
    sock.on('game:state_update',d=>sock._states.push(d.gameState));
    sock.on('game:full_state',d=>sock._full.push(d.gameState));
    sock.on('connect',()=>res(sock));
    sock.on('connect_error',e=>rej(new Error('connect: '+e.message)));
    setTimeout(()=>rej(new Error('connect timeout')),8000);
  });
}
const emitAck=(sock,ev,data)=>new Promise(res=>{sock.emit(ev,data,r=>res(r));setTimeout(()=>res(null),6000);});

(async()=>{
  const [t1,t2,ts]=[await tokenFor('1'),await tokenFor('2'),await tokenFor('s')];
  const p1=await connect(t1), p2=await connect(t2), spec=await connect(ts);
  log('sockets connectés: p1=',p1.id,'p2=',p2.id,'spec=',spec.id);
  const created=await emitAck(p1,'room:create',{settings:{gameMode:'quick',numberOfPlayers:4,isPublic:false,minPlayers:2,maxPlayers:4,fillBots:true},clientId:'c1'});
  const code=created?.room?.id||created?.roomCode; log('room',code);
  await emitAck(p2,'room:join',{roomCode:code,clientId:'c2'});
  await emitAck(p1,'room:ready',{roomCode:code,ready:true});
  await emitAck(p2,'room:ready',{roomCode:code,ready:true});
  await emitAck(p1,'room:start_game',{roomCode:code,fillBots:true});
  await wait(2500);
  // mémorisation terminée pour les 2 humains
  p1.emit('player:ready',{roomCode:code}); p2.emit('player:ready',{roomCode:code});
  await wait(3500);
  // spectateur rejoint en pleine partie
  await emitAck(spec,'room:join',{roomCode:code,clientId:'cs'});
  await wait(2000);
  // attendre un tour HUMAIN (les bots jouent seuls et font avancer les tours)
  let drawer=null;
  for(let i=0;i<40 && !drawer;i++){
    const st=[...p1._states,...p1._full].at(-1);
    const curId=st?.players?.[st.currentPlayerIndex]?.id;
    if(curId===p1.id)drawer=p1; else if(curId===p2.id)drawer=p2; else await wait(1000);
  }
  if(!drawer){log('⚠️ aucun tour humain atteint en 40s');process.exit(1);}
  log('tour humain atteint:', drawer===p1?'p1':'p2');
  // reset captures avant l'action
  [p1,p2,spec].forEach(s=>{s._states.length=0;});
  const actor = drawer;
  await emitAck(actor,'game:draw_card',{roomCode:code});
  await wait(2500);
  const drawnOf=s=>{const g=s._states.at(-1); return g? g.drawnCard : undefined;};
  const val=c=> c==null?'null' : (c.hidden===true?'{hidden}':JSON.stringify({value:c.value,suit:c.suit}));
  log('=== drawnCard reçu par chacun après game:draw_card ==='); 
  log('  actor (pioche):', val(drawnOf(actor)));
  log('  autre joueur  :', val(drawnOf(actor===p1?p2:p1)));
  log('  SPECTATEUR    :', val(drawnOf(spec)));
  const specDrawn=drawnOf(spec), otherDrawn=drawnOf(actor===p1?p2:p1);
  const leaked = c=> c && c.hidden!==true && c.value!==undefined;
  const actorDrawn=drawnOf(actor); const ok = actorDrawn && actorDrawn.value!==undefined && !leaked(specDrawn) && !leaked(otherDrawn);
  console.log(ok?'\n✅ PREUVE SOCKET : le pilocheur reçoit sa carte, mais l\'adversaire ET le spectateur reçoivent {hidden} (payload réel)':'\n❌ souci: '+JSON.stringify({actorDrawn:val(actorDrawn),other:val(otherDrawn),spec:val(specDrawn)}));
  [p1,p2,spec].forEach(s=>s.close()); process.exit(ok?0:1);
})().catch(e=>{console.error('❌',e.message);process.exit(1);});
