#!/usr/bin/env python3
"""Real-device app-level regression for Haku selection, foreground, and share UI.

Uses the installed Haku table callback through a temporary Frida agent. This is
not physical touch or XCTest. Wake/activate Haku and dismiss existing exports
before running. Only the explicitly selected app is restarted by capture.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import threading
import time


AGENT = r'''
const ObjC=bridge;
const cfg=CONFIG;
const invalidBackgroundTask=Module.getGlobalExportByName('UIBackgroundTaskInvalid').readU64().toString();
let controller=null,interval=null,finished=false;
function finish(result){if(finished)return;finished=true;if(interval)clearInterval(interval);send({event:'result',...result});}
function string(o){return o&&!o.isNull()?o.toString():null;}
function tree(){
 const app=ObjC.classes.UIApplication.sharedApplication();
 let vc=app.delegate().window().rootViewController();const chain=[];
 for(let i=0;i<12;i++){
  chain.push(vc.$className);
  const p=vc.presentedViewController();if(p&&!p.isNull()){vc=p;continue;}
  if(vc.respondsToSelector_(ObjC.selector('topViewController'))){vc=vc.topViewController();continue;}
  break;
 }
 return {app,vc,chain};
}
ObjC.schedule(ObjC.mainQueue,()=>{
 try{
  if(ObjC.classes.NSBundle.mainBundle().bundleIdentifier().toString()!=='com.jacklee.haku')throw Error('Attached process is not the Haku app');
  const t=tree();if(Number(t.app.applicationState())!==0)throw Error('Wake and activate Haku first');
  if(t.vc.$className!=='HakuApplicationsController')throw Error('Return Haku to the application list first');
  const c=t.vc;
  c.search().setActive_(true);c.search().searchBar().setText_(cfg.query);
  c.updateSearchResultsForSearchController_(c.search());
  setTimeout(()=>ObjC.schedule(ObjC.mainQueue,()=>{
   try{
    const apps=c.filtered();let index=-1;
    for(let i=0;i<apps.count();i++)if(apps.objectAtIndex_(i).objectForKey_('bundle').toString()===cfg.bundle){index=i;break;}
    if(index<0)throw Error('Selected bundle is absent from the real filtered list');
    // Exercise restoration of a prior false value. The capture must set its
    // own idle assertion and return this value when finished.
    t.app.setIdleTimerDisabled_(false);
    const path=ObjC.classes.NSIndexPath.indexPathForRow_inSection_(index,0);
    c.tableView_didSelectRowAtIndexPath_(c.tableView(),path);
    send({event:'selected',bundle:cfg.bundle,search_active:!!c.search().isActive()});
    interval=setInterval(()=>ObjC.schedule(ObjC.mainQueue,()=>{
     if(finished)return;
     try{
      const u=tree(),state=Number(u.app.applicationState());
      const sample={event:'sample',state,chain:u.chain,idle_disabled:!!u.app.isIdleTimerDisabled()};
      if(u.vc.$className==='HakuCaptureController'){
       controller=u.vc;sample.directory=string(controller.directory());sample.status=string(controller.status().text());
       sample.spinner=!!controller.spinner().isAnimating();sample.background_task=controller.backgroundTask().toString();
      }
      send(sample);
      if(state!==0){finish({status:'failed',reason:'Haku left the foreground during capture',sample});return;}
      if(controller && !sample.spinner){
       if(sample.status!=='Export verified')throw Error('Capture failed: '+sample.status);
       if(sample.idle_disabled)throw Error('Capture did not restore the prior idle timer value');
       if(sample.background_task!==invalidBackgroundTask)throw Error('Capture did not end its background task');
       clearInterval(interval);interval=null;
       const log=string(controller.log().text());controller.share();
       setTimeout(()=>ObjC.schedule(ObjC.mainQueue,()=>{
        const v=tree();
        finish({status:v.chain.includes('UIActivityViewController')?'passed':'failed',
         reason:v.chain.includes('UIActivityViewController')?null:'Share sheet did not appear',
         directory:sample.directory,log,share_chain:v.chain});
       }),400);
      }
     }catch(e){finish({status:'failed',reason:String(e)});}
    }),250);
   }catch(e){finish({status:'failed',reason:String(e)});}
  }),400);
 }catch(e){finish({status:'failed',reason:String(e)});}
});
'''


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--udid',required=True)
    parser.add_argument('--bundle',required=True)
    parser.add_argument('--query',help='Search text; defaults to the selected bundle ID')
    parser.add_argument('--output',type=Path,required=True,help='New private evidence directory')
    parser.add_argument('--timeout',type=float,default=120)
    args=parser.parse_args()
    if not 5<=args.timeout<=600:parser.error('--timeout must be between 5 and 600 seconds')
    args.output.mkdir(parents=True,exist_ok=False)
    import frida
    spec=importlib.util.find_spec('frida_tools')
    if not spec or not spec.origin:raise RuntimeError('Use a Python environment with frida-tools')
    bridge=(Path(spec.origin).parent/'bridges/objc.js').read_text()
    code=bridge+'\n'+AGENT.replace('CONFIG',json.dumps({'bundle':args.bundle,'query':args.query or args.bundle}))
    complete=threading.Event();result={'status':'failed','reason':'No completed UI result before deadline'}
    start=time.monotonic();session=None
    cancel=frida.Cancellable();timer=threading.Timer(args.timeout,cancel.cancel);timer.daemon=True;timer.start()
    try:
        with (args.output/'trace.jsonl').open('w') as trace, cancel:
            device=frida.get_device(args.udid,timeout=5)
            if device.id!=args.udid or device.type!='usb':raise RuntimeError('Exact USB device unavailable')
            process=device.get_process('Haku');session=device.attach(process.pid)
            script=session.create_script(code)
            def received(message,data):
                nonlocal result
                item={'elapsed':round(time.monotonic()-start,3),**message}
                trace.write(json.dumps(item)+'\n');trace.flush()
                payload=message.get('payload',{})
                if payload.get('event')=='result':result=payload;complete.set()
                elif message.get('type')=='error':result={'status':'failed','reason':message.get('description')};complete.set()
            script.on('message',received);script.load();complete.wait(max(0,args.timeout-(time.monotonic()-start)))
    except Exception as error:result={'status':'failed','reason':str(error)}
    finally:
        try:
            if session:
                with cancel:session.detach()
        except Exception as error:result['detach_error']=str(error)
        timer.cancel()
    result.update(elapsed_seconds=round(time.monotonic()-start,3),verification='physical-device app-level UIKit callback; not touch/XCTest')
    (args.output/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
    return 0 if result['status']=='passed' else 1


if __name__=='__main__':raise SystemExit(main())
