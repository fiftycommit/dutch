// Preuve : Playwright pilote une VRAIE partie entre DEUX clients, uniquement par
// sélecteurs sémantiques (aucune coordonnée pixel), grâce aux Semantics ajoutés sur
// la table de jeu. Séquence : connexion des 2, création/join d'un salon privé,
// lancement, MÉMORISATION (sélection de 2 cartes par sélecteur), puis pioche +
// remplacement (client au tour) + pioche + défausse (client suivant).
// Prérequis : stack émulateurs + build web ENABLE_SEMANTICS=true (voir DEV-EMULATORS.md).
import { chromium } from 'playwright';
import { openMultiplayerAuth, fillField, boxByText, boxByLabel, tap, waitBox } from './flutter-semantics.mjs';
const URL='http://localhost:8081/', SERVER='http://localhost:3000';
const log=(...a)=>console.log(new Date().toISOString().slice(11,19),...a);

async function seed(){ const id=Date.now().toString().slice(-8)+Math.floor(Math.random()*9);
  const email=`gp${id}@example.com`, name=`GP${id}`;
  const r=await fetch(`${SERVER}/api/auth/register-password`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:`gp${id}`,displayName:name,email,password:'MotDePasse123'})});
  if(r.status!==201) throw new Error('seed '+r.status); return {email,name};
}
function attach(p){ p._ok=false; p.on('response',r=>{if(r.url().includes('/api/auth/login-password')&&r.status()===200)p._ok=true;}); }
async function login(p,email,who){ for(let a=1;a<=6&&!p._ok;a++){ await p.goto(URL+'?rebuildprobe=1',{waitUntil:'load'}); await p.waitForTimeout(9000); await openMultiplayerAuth(p); await fillField(p,"E-mail ou nom d'utilisateur",email); await fillField(p,'Mot de passe','MotDePasse123'); await tap(p,await boxByText(p,/^SE CONNECTER$/)); for(let i=0;i<8&&!p._ok;i++)await p.waitForTimeout(1000);} if(!p._ok)throw new Error(who+' login KO'); await p.waitForTimeout(2500); }
// Flutter web expose le label Semantics en textContent (role=button). On cible par texte.
const hasText=(p,re,enabledOnly=false)=>p.evaluate(({src,e})=>{const rx=new RegExp(src,'i');const els=[...document.querySelectorAll('[role="button"]')].filter(x=>rx.test((x.textContent||'').trim())&&x.getBoundingClientRect().width>0&&x.getBoundingClientRect().y>=0);if(!els.length)return false;if(!e)return true;return els.some(x=>x.getAttribute('aria-disabled')!=='true');},{src:re.source,e:enabledOnly});
const tapText=async(p,re)=>{const b=await boxByText(p,re);if(!b)throw new Error('texte absent '+re.source);await tap(p,b);};

(async()=>{
  const uA=await seed(), uB=await seed();
  const br=await chromium.launch({headless:true});
  const A=await(await br.newContext({viewport:{width:1400,height:900}})).newPage();
  const B=await(await br.newContext({viewport:{width:1400,height:900}})).newPage();
  attach(A); attach(B);
  await login(A,uA.email,'A');
  // créer salon
  await tap(A,await waitBox(A,()=>boxByText(A,/Créer un salon/))); await A.waitForTimeout(2000);
  await tap(A,await waitBox(A,()=>boxByText(A,/Salon Privé/))); await A.waitForTimeout(2000);
  await tap(A,await waitBox(A,()=>boxByText(A,/CRÉER LE SALON/))); await A.waitForTimeout(4000);
  const code=await A.evaluate(()=>{for(const e of document.querySelectorAll('flt-semantics')){const t=(e.textContent||'').trim();if(/^[A-Z0-9]{8}$/.test(t))return t;}return null;});
  log('code',code);
  await login(B,uB.email,'B');
  await tap(B,await waitBox(B,()=>boxByText(B,/Rejoindre un salon/))); await B.waitForTimeout(2500);
  const priv=await boxByText(B,/Salon Privé|privé/i); if(priv){await tap(B,priv);await B.waitForTimeout(2500);}
  const inp=await B.evaluate(()=>{const e=document.querySelector('input');if(!e)return null;const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};}); await B.mouse.click(inp.x,inp.y); await B.waitForTimeout(500); await B.keyboard.insertText(code); await B.waitForTimeout(500);
  await tap(B,await boxByText(B,/REJOINDRE/i)); await B.waitForTimeout(3500);
  // prêts + lancement
  for(const [p,w] of [[B,'B'],[A,'A']]){ const r=await boxByText(p,/Passer pret/i); if(r){await tap(p,r);await p.waitForTimeout(1200);} }
  await A.waitForTimeout(1500);
  await tap(A,await boxByText(A,/Lancer/i)); await A.waitForTimeout(1800);
  const cf=await boxByText(A,/^Lancer$/i); if(cf)await tap(A,cf); await A.waitForTimeout(9000);
  // MÉMORISATION par sélecteur (2 cartes) sur chaque client
  for(const [p,w] of [[A,'A'],[B,'B']]){
    for(let i=0;i<25;i++){ if(await hasText(p,/^Carte à mémoriser 1$/)) break; await p.waitForTimeout(600);}
    await tapText(p,/^Carte à mémoriser 1$/); await p.waitForTimeout(400);
    await tapText(p,/^Carte à mémoriser 2$/); await p.waitForTimeout(400);
    const ch=await boxByText(p,/CHOISIS 2 CARTES/i); if(ch)await tap(p,ch);
    log(w+' mémorisation faite (par sélecteur)');
  }
  await A.waitForTimeout(6000);
  // JOUER 2 tours : pioche + (remplacement puis défausse), sur le client dont c'est le tour
  const players={A:uA.name,B:uB.name};
  let didDraw=0, didReplace=0, didDiscard=0;
  for(let turn=0;turn<2;turn++){
    let actor=null,who=null;
    for(let poll=0;poll<50&&!actor;poll++){ if(await hasText(A,/PIOCHER/,true)){actor=A;who='A';} else if(await hasText(B,/PIOCHER/,true)){actor=B;who='B';} else await A.waitForTimeout(500); }
    if(!actor){ log('tour '+turn+': aucun PIOCHER actif détecté'); break; }
    log('tour '+turn+': au tour de '+who);
    await tapText(actor,/PIOCHER/); didDraw++; await actor.waitForTimeout(1800); log('  pioché');
    if(turn===0){
      await tapText(actor,new RegExp('^Carte 1 de '+players[who]+'$')); didReplace++; await actor.waitForTimeout(2000); log('  remplacé (carte 1)');
    } else {
      const jeter=await boxByText(actor,/JETER/); if(jeter){await tap(actor,jeter);didDiscard++;await actor.waitForTimeout(2000);log('  défaussé (JETER)');}
    }
  }
  log(`RÉSULTAT: pioche=${didDraw} remplacement=${didReplace} défausse=${didDiscard}`);
  await A.screenshot({path:'/tmp/gp-A.png'});
  const ok = didDraw>=2 && didReplace>=1 && didDiscard>=1;
  console.log(ok?'\n✅ GAMEPLAY PILOTÉ PAR SÉLECTEUR (mémo + pioche + remplacement + défausse, 2 clients)':'\n⚠️ séquence incomplète');
  await br.close(); process.exit(ok?0:1);
})().catch(e=>{console.error('❌',e.message);process.exit(1);});
